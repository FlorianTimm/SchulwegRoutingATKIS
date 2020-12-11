create table if not exists schulweg_neu.flaechen_manuell 
(gid serial, bezeichung varchar(100), erlaubt boolean, geom geometry(Polygon, 25832));
CREATE INDEX if not exists flaechen_manuell_geom 
    ON schulweg_neu.flaechen_manuell USING gist
    (geom);

-- Parks aus sie02_f und Löcher entfernen
drop table if exists schulweg_neu.parks;
create table schulweg_neu.parks as
select nam, objart, objid, geom
--from sdp.sie02_f where objart = '41008' and fkt = '4420'; -- ATKIS
from sdp.sie02_f where objart = '41008' and fkt = '4420';
CREATE INDEX IF NOT EXISTS parks_the_geom
    ON schulweg_neu.parks USING gist(geom);

-- Kleingärten / Friedhöfe
drop table if exists schulweg_neu.kleingaerten_friedhoefe;
create table schulweg_neu.kleingaerten_friedhoefe as
select nam, fkt, (st_dump(st_union(geom))).geom
--from sdp.sie02_f where objart = '41008' and fkt = '4440' --Daten aus ATKIS
from sdp.alkis_nutzung_flaechen where bezeich = 'AX_Friedhof' or (bezeich = 'AX_SportFreizeitUndErholungsflaeche' and bezfkt = 'Kleingarten') --Daten aus ALKIS
group by nam, fkt;
CREATE INDEX IF NOT EXISTS kleingaerten_friedhoefe_the_geom
    ON schulweg_neu.kleingaerten_friedhoefe USING gist(geom);

-- Hagenbecks Tierpark / Niendorfer Gehege mit zu den Kleingärten
insert into schulweg_neu.kleingaerten_friedhoefe
select nam, fkt, (st_dump(st_union(geom))).geom
from sdp.sie02_f where objart = '41008' and nam in ('Niendorfer Gehege', 'Hagenbecks Tierpark') group by nam, fkt;

-- Industrie und Gewerbe
insert into schulweg_neu.kleingaerten_friedhoefe
select nam, fkt, (st_dump(st_union(geom))).geom
from sdp.alkis_nutzung_flaechen
where (bezeich = 'AX_IndustrieUndGewerbeflaeche' and "bezfkt" not in ('Handel und Dienstleistung','Handel''Ausstellung, Messe')) or bezeich = 'AX_Flugverkehr'
group by nam, fkt;

insert into  schulweg_neu.kleingaerten_friedhoefe (geom)
select geom from schulweg_neu.flaechen_manuell where not erlaubt;

drop table if exists tmp_kleingaerten;
create temporary table tmp_kleingaerten as
with 
erlaubt as (select st_union(geom) geom from schulweg_neu.flaechen_manuell where erlaubt)
select 
--st_buffer(geom,-0.5) -- Buffer für ATKIS
st_difference(geom, (select geom from erlaubt)) geom 
from schulweg_neu.kleingaerten_friedhoefe;
CREATE INDEX IF NOT EXISTS tmp_kleingaerten_the_geom
    ON tmp_kleingaerten USING gist(geom);
	
	
-- Teilen an alle KGV und Park-Grenzen
create temporary table tmp_part as
with
flaechen as (select st_boundary(geom) geom from tmp_kleingaerten union select st_boundary(geom) from schulweg_neu.parks),
gruppe as (select n.*, st_union(f.geom) teiler from schulweg_neu.routing_aktuell n, flaechen f where n.gewicht = 1 and bwf=0 and st_crosses(the_geom, geom) group by n.gid),
teilung as (select *, (st_dump(st_split(the_geom, teiler))) geteilt_dump from gruppe)
select *, (geteilt_dump).geom geteilt, (geteilt_dump).path[1] part from teilung;

-- dem alten Datensatz die Geometrie des ersten Teiles zuweisen
update schulweg_neu.routing_aktuell set the_geom = geteilt
from tmp_part where part = 1 and tmp_part.gid = routing_aktuell.gid;

-- weitere Teile hinzufügen
insert into schulweg_neu.routing_aktuell(objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, gewicht, date, the_geom)
select objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, gewicht, date, geteilt the_geom from tmp_part where part > 1;
drop table if exists tmp_part;

-- Gewicht hochdrehen
update schulweg_neu.routing_aktuell set gewicht = 999 
from tmp_kleingaerten k where st_within(routing_aktuell.the_geom, st_buffer(k.geom,0.1));

-- Wegenamen 
update schulweg_neu.routing_aktuell 
set nam = concat('Weg im ', park.nam)
from (select nam, geom from schulweg_neu.parks where nam is not null and nam != '') park where
st_within(routing_aktuell.the_geom, park.geom)
and gewicht = 1 and bwf = 0 and (routing_aktuell.nam = '' or routing_aktuell.nam is null);