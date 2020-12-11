-- Erzeugt das Grundnetz aus ATKIS Daten
-- 2020-12-01


-- Schema erzeugen falls nicht vorhanden
create schema if not exists schulweg_neu;

-- Tabelle für Netz generieren
drop table if exists schulweg_neu.routing_aktuell;
create table if not exists schulweg_neu.routing_aktuell (
	gid serial primary key,
	objid character (16),
	objart integer,
	objart_txt character (50),
	fkt integer,
	nam character (255),
	bwf integer,
	bdi integer,
	wdm character (20),
	gewicht integer default 1,
	date date,
	length double precision,
	x1 double precision,
	y1 double precision,
	x2 double precision,
	y2 double precision,
	source integer,
	target integer,
	the_geom geometry(LineString, 25832)
	);

-- Geographischen Index erzeugen (beschleunigt weitere Abfragen)
CREATE INDEX routing_aktuell_the_geom
    ON schulweg_neu.routing_aktuell USING gist
    (the_geom);
	
--truncate schulweg_neu.routing_aktuell;

-- Straßen aus ver01_l
insert into schulweg_neu.routing_aktuell (objid, objart, objart_txt, fkt, nam, bdi, wdm, date, the_geom)
select objid, objart::integer, objart_txt, NULLIF(fkt,'')::integer, nam, NULLIF(bdi,'')::integer, wdm, to_timestamp(beginn,'YYYY-MM-DDTHH:MI:SSZ') date, (st_dump(geom)).geom from sdp.ver01_l where objart in ('42003','42005') and wdm != '1301' and st_isvalid(geom);

-- Fahrweg-Achsen aus ver02_l
insert into schulweg_neu.routing_aktuell (objid, objart, objart_txt, fkt, nam, date, the_geom)
select objid, objart::integer, objart_txt, NULLIF(fkt,'')::integer, nam, to_timestamp(beginn,'YYYY-MM-DDTHH:MI:SSZ') date, (st_dump(geom)).geom from sdp.ver02_l where objart = '42008' and st_isvalid(geom);


-- WegPfadSteig aus ver02_l
insert into schulweg_neu.routing_aktuell (objid, objart, objart_txt, fkt, nam, date, the_geom)
select objid, objart::integer, objart_txt, NULLIF(art,'')::integer fkt, nam, to_timestamp(beginn,'YYYY-MM-DDTHH:MI:SSZ') date, (st_dump(geom)).geom from sdp.ver02_l where objart = '53003' and st_isvalid(geom);

-- Harburger Umgehung / Wilhelmsburger Reichsstraße entfernen (Bundesstraße freie Strecke ohne Fuß/Radweg)
update schulweg_neu.routing_aktuell set gewicht = 999 where nam in ('Harburger Umgehung','Wilhelmsburger Reichsstraße');

--select st_astext(st_split(ST_GeomFromText('LINESTRING(0 10, 10 0)'),  ST_GeomFromText('LINESTRING(0 0, 10 10)')))


-- doppelte Geometrien löschen
delete from schulweg_neu.routing_aktuell where gid in
(select a.gid from schulweg_neu.routing_aktuell a, schulweg_neu.routing_aktuell b 
where a.gid > b.gid and a.bwf = b.bwf and 
st_equals(a.the_geom, b.the_geom));

-- Schnipsel, die von anderen abgedeckt werden löschen
delete from schulweg_neu.routing_aktuell where gid in
(select a.gid from schulweg_neu.routing_aktuell a, schulweg_neu.routing_aktuell b 
where a.gid <> b.gid and a.bwf = b.bwf and 
st_within(a.the_geom, st_buffer(b.the_geom, 0.1))
and 
not st_within(b.the_geom, st_buffer(a.the_geom, 0.1))
and st_length(a.the_geom) < st_length(b.the_geom));
