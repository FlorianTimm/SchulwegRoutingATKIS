CREATE OR REPLACE FUNCTION teilen() RETURNS INT AS
$BODY$
DECLARE
	vorher integer := 0;
BEGIN

	create temporary table tmp_sackgassen as

		--Sackgasse an Startpunkt
		select gid sackgasse, v.id knoten, v.the_geom punkt, 0 pkt_nr from 
		schulweg_neu.routing_aktuell n, schulweg_neu.routing_aktuell_vertices_pgr v where (v.cnt = 1 or v.chk = 1) and
		n.source = v.id;

		--Sackgasse an Endpunkt
		insert into tmp_sackgassen
		select gid sackgasse, v.id knoten, v.the_geom punkt, -1 pkt_nr from 
		schulweg_neu.routing_aktuell n, schulweg_neu.routing_aktuell_vertices_pgr v where (v.cnt = 1 or v.chk = 1) and
		n.target = v.id;
		
	LOOP
	
		
		
		vorher := (select count(*) from tmp_sackgassen);

		-- auf Knoten in der Nähe snappen
		create temporary table tmp_knoten_verschmelzen as
		select distinct on (s.sackgasse) s.sackgasse, s.knoten, v.the_geom punkt, s.pkt_nr, v.id neuer_knoten
		from schulweg_neu.routing_aktuell_vertices_pgr v, tmp_sackgassen s 
		where s.knoten != v.id and st_dwithin(v.the_geom, s.punkt, 3) order by s.sackgasse, st_distance(v.the_geom, s.punkt) ;

		delete from schulweg_neu.routing_aktuell_vertices_pgr where id in (select knoten from tmp_knoten_verschmelzen);
		update schulweg_neu.routing_aktuell_vertices_pgr set cnt = cnt + 1 where id in (select neuer_knoten from tmp_knoten_verschmelzen);
		update schulweg_neu.routing_aktuell set 
		source = CASE WHEN pkt_nr = 0 then neuer_knoten else source END,
		target = CASE WHEN pkt_nr = -1 then neuer_knoten else target END,
		the_geom = st_setpoint(the_geom, pkt_nr, punkt)
		from tmp_knoten_verschmelzen where sackgasse = gid;

		delete from tmp_sackgassen where knoten in (select knoten from tmp_knoten_verschmelzen);

		-- Linien teilen
		create temporary table tmp_abschnitte_teilen as
		with
		sackgassen_punkt as (select distinct on (s.sackgasse) knoten, s.sackgasse, ST_ClosestPoint(s.punkt,n.the_geom) punkt, pkt_nr, n.gid abschnitt, the_geom
			from schulweg_neu.routing_aktuell n, tmp_sackgassen s 
			where --n.bwf = 0 and 
			target != knoten and source != knoten and s.sackgasse != n.gid and st_dwithin(n.the_geom, punkt, 3) 
			order by s.sackgasse, st_distance(n.the_geom, punkt)),
		distinct_abschnitt as 
			(select distinct on (abschnitt) * from sackgassen_punkt),
		splitting as 
			(select knoten, sackgasse, punkt, pkt_nr, abschnitt, st_dump(st_split(st_snap(the_geom, punkt, 3), punkt)) trennung from distinct_abschnitt)
		select knoten, sackgasse, punkt, pkt_nr, abschnitt, (trennung).geom geom, (trennung).path[1] nr from splitting;

		-- Teilungsvorschläge ohne Teilung entfernen
		delete from tmp_abschnitte_teilen where abschnitt in (
		select abschnitt from tmp_abschnitte_teilen group by abschnitt, sackgasse having max(nr) != 2 and count(*) != 2);

		-- Anzahl der Kanten des Knoten erhöhen
		update schulweg_neu.routing_aktuell_vertices_pgr 
		set cnt = cnt + 2, chk = 0 where id in (select knoten from tmp_abschnitte_teilen);

		-- Eintrag des geteilten Abschnittes anpassen
		update schulweg_neu.routing_aktuell set
		target = knoten,
		the_geom = geom
		from tmp_abschnitte_teilen where abschnitt = gid and nr = 1;

		-- neuen Eintrag für zweite Hälfte des geteilten Abschnittes
		insert into schulweg_neu.routing_aktuell (objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, date, source, target, the_geom)
				select objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, date, knoten, target, geom the_geom
				from tmp_abschnitte_teilen, schulweg_neu.routing_aktuell where abschnitt = gid and nr = 2;

		-- Endpunkt des neu angebundenen Abschnittes anpassen
		-- TODO mitgezogene Abschnitte auch anpassen (alle Abschnitte, die Knoten verwenden, der verschoben wurde)
		update schulweg_neu.routing_aktuell set
		the_geom = st_setpoint(the_geom, pkt_nr, punkt)
		from tmp_abschnitte_teilen where sackgasse = gid;

		-- Koordinaten des Knoten anpassen
		update schulweg_neu.routing_aktuell_vertices_pgr set
		the_geom = punkt
		from tmp_abschnitte_teilen where knoten = id;

		-- bearbeitete Abschnitte aus Liste entfernen
		delete from tmp_sackgassen where knoten in (select knoten from tmp_abschnitte_teilen);
		vorher := vorher - (select count(*) from tmp_sackgassen);
		RAISE NOTICE '% Fehler behoben!', vorher;

		drop table if exists tmp_knoten_verschmelzen;
		drop table if exists tmp_abschnitte_teilen;
		
		EXIT WHEN vorher = 0;

		END LOOP;
		
		drop table if exists tmp_sackgassen;

    RETURN vorher;
END
$BODY$
LANGUAGE plpgsql;

SELECT * FROM teilen();

drop table if exists schulweg_neu.sackgassen_neu;
create table schulweg_neu.sackgassen_neu as
select b.* from 
schulweg_neu.routing_aktuell_vertices_pgr b left join
schulweg_neu.deny_sackgassen a
on st_dwithin(a.the_geom, b.the_geom, 3) where b.cnt = 1 and a.the_geom is null;