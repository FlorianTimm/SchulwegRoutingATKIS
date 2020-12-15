-- Generiert Wege über Plätze
-- 2020-12-01

-- Plätze aus ver01_f filtern
drop table if exists tmp_plaetze;
create temporary table tmp_plaetze as
with
plaetze1 as
(select fkt, nam, objart, objart_txt, objid, sts, geom from sdp.ver01_f where objart = '42009' and fkt in ('5130','5350')),

-- Plätze vergleichen
plaetze2 as
(select row_number() over () id, nam, st_unaryunion(geom) geom from 
(select nam, unnest(st_clusterwithin(geom, 0.1)) geom 
 from plaetze1 group by nam) b)
 
select distinct on (j.id) p.objid, j.nam, p.fkt, j.geom from 
plaetze2 j, plaetze1 p where j.nam = p.nam and st_within(p.geom, j.geom) order by j.id, st_area(p.geom) desc;

-- update bisherige Plätze
update schulweg_neu.deny_plaetze set 
nam = q.nam,
fkt = q.fkt,
the_geom = q.geom
from (select objid, nam, fkt::int, geom from tmp_plaetze) as q
where deny_plaetze.objid = q.objid;

-- neue Plätze
insert into schulweg_neu.deny_plaetze
select objid, nam, NULL bdi, NULL bez, fkt::int, NULL wdm, 1 gewicht, 1000 status, 4000 wegeerzeugung, 
2000 nacharbeit, geom the_geom 
from tmp_plaetze where objid not in (select objid from schulweg_neu.deny_plaetze);

-- nicht gefundene Plätze
update schulweg_neu.deny_plaetze set status = 3000 where objid not in (select objid from tmp_plaetze);

drop table tmp_plaetze;


--wegerzeugung 
-- 3000 Querung
-- 2000 Umring
-- 4000 alle
-- 1000 keine

-- Punkte
drop table if exists tmp_plaetze_punkte;
create temporary table tmp_plaetze_punkte (
id serial primary key,
objid character (16),
geom geometry(Point, 25832));

-- Schnittpunkte mit Wegen = Zuwegung zum Platz
insert into tmp_plaetze_punkte(objid, geom)
select a.objid,
(st_dump(
	case when st_geometrytype(geom) = 'ST_LineString' 
	then st_collect(st_startpoint(geom),st_endpoint(geom) ) 
	else geom end)).geom
from
(select p.objid, (st_dump(st_intersection(n.the_geom, ST_Boundary(p.the_geom)))).geom geom from schulweg_neu.deny_plaetze p, schulweg_neu.routing_aktuell n where n.bwf = 0 and p.wegerzeugung != 1000 and (st_touches(p.the_geom, n.the_geom) or st_intersects(p.the_geom, n.the_geom))) a;

-- Eigene, konkave Stützpunkte für Plätze, die gequeert werden können (zB bei L förmigen Plätzen kürzere Wege)
insert into tmp_plaetze_punkte (objid, geom) 
with points as (select objid, (dump_geom).path[1] nr, max_nr, (dump_geom).geom from (
select objid, st_npoints(the_geom) max_nr, st_dump(st_points(ST_ForceRHR(the_geom))) dump_geom
from schulweg_neu.deny_plaetze p where p.wegerzeugung in (3000,4000)) a)

select b.objid, b.geom from points a, points b, points c where a.objid = b.objid and b.objid = c.objid and 
b.nr != b.max_nr and
a.nr = case when b.nr = 1 then b.max_nr - 1 else b.nr - 1 end and
c.nr = b.nr + 1 and
ST_Contains(ST_Buffer(st_makeline(a.geom, c.geom), 100, 'side=right'), b.geom);

drop table if exists tmp_plaetze_punkte_distinct;
create temporary table tmp_plaetze_punkte_distinct as
select distinct on (objid, geom) * from tmp_plaetze_punkte;

drop table if exists tmp_wege_ueber_plaetze;
create table tmp_wege_ueber_plaetze (
	objid character (16),
	nam character (255),
	geom geometry(LineString, 25832));

-- Umring 
insert into tmp_wege_ueber_plaetze
select p.objid, 
CASE WHEN p.nam != '' and p.nam is not null then concat('Weg um ', p.nam) else null end as nam, 
(st_dump(st_split(ST_Boundary(p.the_geom), a.geom))).geom from 
schulweg_neu.deny_plaetze p,
(select objid, st_collect(geom) geom from tmp_plaetze_punkte_distinct group by objid) a
 where a.objid = p.objid and p.wegerzeugung in (2000,4000);
 
-- Querung
insert into tmp_wege_ueber_plaetze
select p.objid, concat('Weg über ', p.nam), c.geom from 
(select a.objid, st_makeline(a.geom, b.geom) geom from tmp_plaetze_punkte_distinct a, tmp_plaetze_punkte_distinct b where a.id != b.id and a.objid = b.objid and a.id > b.id) c,
schulweg_neu.deny_plaetze p where c.objid = p.objid and p.wegerzeugung in (3000,4000) and st_within(c.geom, p.the_geom) and st_intersects(c.geom, st_buffer(p.the_geom,-0.01));

 
insert into schulweg_neu.routing_aktuell (objid, nam, the_geom)
select objid, nam, geom from tmp_wege_ueber_plaetze;
