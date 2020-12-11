-- Führt die Verschneidung mit Bauwerken (Brücken/Tunnel) durch
-- 2020-12-01

-- Temporäre Tabelle mit den gewünschten Bauwerken
create temporary table bruecken_tunnel as
-- Bruecken/Tunnel aus ver06_l filtern
select bwf, nam, objart, objid, objart_txt, geom from sdp.ver06_l where objart = '53001'
union
-- Bruecken/Tunnel aus ver06_f filtern
select bwf, nam, objart, objid, objart_txt, geom from sdp.ver06_f where objart = '53001';


----Abgleich mit bisherigen Daten

-- update bisherige Bruecken
update schulweg_neu.deny_bruecken_tunnel set 
nam = q.nam,
bwf = q.bwf,
the_geom = q.geom
from (select objid, nam, bwf::int, geom from bruecken_tunnel) as q
where deny_bruecken_tunnel.uuid = q.objid;

-- neue Brücken/Tunnel
insert into schulweg_neu.deny_bruecken_tunnel
select objid uuid, bwf::int, nam, 1000 status, 1000 begehbar, geom the_geom 
from bruecken_tunnel where objid not in (select uuid from schulweg_neu.deny_bruecken_tunnel);

-- nicht gefundene Plätze
update schulweg_neu.deny_bruecken_tunnel set status = 3000 where uuid not in (select objid from bruecken_tunnel);


-- Verknüpfung Weg/Bauwerk
create temporary table hdu as
select objid_1, b.bwf bwf_bt, b.nam, b.begehbar from sdp.hdu01_b h
	left join schulweg_neu.deny_bruecken_tunnel b on h.objid_2 = b.uuid
where h.objart_2 = '53001' and h.objart_1 in ('42003', '42005', '42008', '53003');

-- Standardwert für Bauwerk setzen
update schulweg_neu.routing_aktuell set bwf = 0;


-- Wegen den Bauwerkstyp zuweisen
update schulweg_neu.routing_aktuell 
set bwf = hdu.bwf_bt::int
-- gewicht = case when hdu.begehbar = 2000 then 1000 else 0 end
from (select objid_1, bwf_bt, begehbar from hdu) hdu 
where hdu.objid_1 = objid;

-- Wege von nicht begehbaren Brücken/Tunnel löschen
update schulweg_neu.routing_aktuell set gewicht = 999 where objid 
in (select objid_1 from hdu where begehbar = 2000);

-- Wegname von Brücke/Tunnel, wenn bisher kein Name
update schulweg_neu.routing_aktuell 
set nam = hdu.nam
from (select * from hdu where nam is not null and nam != '') hdu where
hdu.objid_1 = objid
and routing_aktuell.nam = '' or routing_aktuell.nam is null;