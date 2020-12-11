
		drop table if exists tmp_schulweg_cuts;
		create temporary table tmp_schulweg_cuts as 
			select distinct on (gid, (parts).path[1])
			gid,
			(parts).path[1] path,
			objid,
			objart,
			objart_txt,
			fkt,
			nam,
			bwf,
			bdi,
			wdm,
			date, 
			case when (parts).path[1] = 1 then source else neu end source, 
			case when (parts).path[1] = 1 then neu else target end target,
			(parts).geom from (
			select a.*, b.id neu,
			st_dump(st_split(ST_Snap(a.the_geom, b.the_geom,1), b.the_geom)) as parts FROM
			schulweg_neu.routing_aktuell AS a,
			schulweg_neu.routing_aktuell_vertices_pgr AS b
			WHERE a.source != b.id and a.target != b.id and b.chk = 1 and st_dwithin(a.the_geom,b.the_geom,1)) c;-- limit 20
		EXIT WHEN (select count(*) from tmp_schulweg_cuts) = 0;
		count := count  + (select count(*) from tmp_schulweg_cuts);
		update schulweg_neu.routing_aktuell set the_geom = c.geom, source = c.source, target = c.target
		from (select gid, geom, source, target from tmp_schulweg_cuts where path = 1) c where routing_aktuell.gid = c.gid;

		insert into schulweg_neu.routing_aktuell (objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, date, source, target, the_geom)
		select objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, date, source, target, geom the_geom
		from tmp_schulweg_cuts where path = 2;
		
		update schulweg_neu.routing_aktuell_vertices_pgr set
		chk = 0, 
		cnt = cnt + 2,
		the_geom = st_endpoint(geom) from tmp_schulweg_cuts where id = target and path = 1;
		
		
		
		
		
		
		
		with
a as (select a.gid aid, a.the_geom abschnitt, v.id pid, v.the_geom punkt
	  from schulweg_neu.routing_aktuell_vertices_pgr v, schulweg_neu.routing_aktuell a 
	  where v.chk = 1 and a.source != v.id and a.target != v.id and st_dwithin(v.the_geom, a.the_geom, 3)),
b as (select *, st_split(abschnitt, st_snap(punkt, abschnitt, 4)) split from a),
c as (select *, st_dump(split) dump from b),
d as (select *, (dump).path[1] nr from c where (dump).path[1] = 2)
select *, st_dump(split) from b;


delete from schulweg_neu.routing_aktuell where not st_isvalid(the_geom) and source = target;



-- Abschnitte werden doppelt verwendet, wenn 3 in Folge zusammen passen a-b-c wird zu ab und bc
-- evtl loop und jedes Mal nur einen Abschnitt verbinden
create table schulweg_neu.join as 
select st_linemerge(st_collect(a.the_geom, b.the_geom)) from schulweg_neu.routing_aktuell a, schulweg_neu.routing_aktuell b, schulweg_neu.routing_aktuell_vertices_pgr p where
p.cnt = 2 and 
p.id = a.source and 
a.source = b.target and 
--a.objid = b.objid and 
a.gewicht = b.gewicht and 
a.gid < b.gid and 
a.nam = b.nam and 
a.gewicht = b.gewicht;


create table schulweg_neu.dupl as 
select a.the_geom from schulweg_neu.routing_aktuell a, schulweg_neu.routing_aktuell b 
where a.gid > b.gid and a.bwf = b.bwf and 
st_equals(a.the_geom, b.the_geom);

insert into schulweg_neu.dupl 
select a.the_geom from schulweg_neu.routing_aktuell a, schulweg_neu.routing_aktuell b 
where a.gid <> b.gid and a.bwf = b.bwf and 
st_within(a.the_geom, st_buffer(b.the_geom, 0.1))
and 
not st_within(b.the_geom, st_buffer(a.the_geom, 0.1))
and st_length(a.the_geom) < st_length(b.the_geom);