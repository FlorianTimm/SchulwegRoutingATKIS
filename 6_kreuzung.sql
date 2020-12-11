-- mit Teilen aus:
/*PGR-GNU*****************************************************************

Copyright (c) 2015 pgRouting developers
Mail: project@pgrouting.org

Author: Nicolas Ribot, 2013
EDITED by Adrien Berchet, 2020

------

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

 ********************************************************************PGR-GNU*/


---------------------------
-- pgr_nodeNetwork
---------------------------





CREATE temporary TABLE tmp_intergeom AS (
    SELECT l1.gid AS l1id,
         l2.gid AS l2id,
         l1.the_geom AS line,
         st_startpoint(l2.the_geom) AS source,
         st_endpoint(l2.the_geom) AS target,
         st_closestPoint(l1.the_geom, l2.the_geom) AS geom
    FROM (SELECT * FROM schulweg_neu.routing_aktuell where bwf = 0 and gewicht < 100) AS l1
    JOIN (SELECT * FROM schulweg_neu.routing_aktuell where bwf = 0 and gewicht < 100) AS l2
    ON (st_dwithin(l1.the_geom, l2.the_geom, 2))
    WHERE l1.gid <> l2.gid AND
    st_within(st_startpoint(l1.the_geom),st_startpoint(l2.the_geom))=false AND
    st_equals(st_startpoint(l1.the_geom),st_endpoint(l2.the_geom))=false AND
    st_equals(st_endpoint(l1.the_geom),st_startpoint(l2.the_geom))=false AND
    st_equals(st_endpoint(l1.the_geom),st_endpoint(l2.the_geom))=false );
	
CREATE temporary TABLE tmp_inter_loc AS (
    SELECT l1id, l2id, st_linelocatepoint(line,point) AS locus FROM (
    SELECT DISTINCT l1id, l2id, line, (ST_DumpPoints(geom)).geom AS point FROM tmp_intergeom) AS foo
    WHERE st_length(line) > 0 and st_linelocatepoint(line,point) between 1./st_length(line) and (1-1./st_length(line)));
	
create temporary table tmp_neue as (  
WITH cut_locations AS
  (
    SELECT l1id AS lid, locus
    FROM tmp_inter_loc
    -- then generates start AND end locus for each line that have to be cut buy a location point
    UNION ALL
    SELECT DISTINCT i.l1id  AS lid, 0 AS locus
    FROM tmp_inter_loc i LEFT JOIN schulweg_neu.routing_aktuell b ON (i.l1id = b.gid)
    UNION ALL
    SELECT DISTINCT i.l1id  AS lid, 1 AS locus
    FROM tmp_inter_loc i LEFT JOIN schulweg_neu.routing_aktuell b ON (i.l1id = b.gid)
    ORDER BY lid, locus
  ),
  -- we generate a row_number index column for each input line
  -- to be able to self-join the table to cut a line between two consecutive locations
  loc_with_idx AS (
    SELECT lid, locus, row_number() OVER (PARTITION BY lid ORDER BY locus) AS idx
    FROM cut_locations
  )
  -- finally, each original line is cut with consecutive locations using linear referencing functions
  SELECT l.gid , loc1.idx AS sub_id, st_linesubstring(l.the_geom, loc1.locus, loc2.locus) AS the_geom
  FROM loc_with_idx loc1 JOIN loc_with_idx loc2 USING (lid) JOIN schulweg_neu.routing_aktuell l ON (l.gid = loc1.lid)
  WHERE loc2.idx = loc1.idx+1
    -- keeps only linestring geometries
    AND geometryType(st_linesubstring(l.the_geom, loc1.locus, loc2.locus)) = 'LINESTRING');
	
update schulweg_neu.routing_aktuell set the_geom = n.the_geom from
tmp_neue n where n.sub_id = 1 and routing_aktuell.gid = n.gid;

insert into schulweg_neu.routing_aktuell
(objid, objart, objart_txt, fkt, nam, bwf, bdi, wdm, date, the_geom)
select a.objid, a.objart, a.objart_txt, a.fkt, a.nam, a.bwf, a.bdi, a.wdm, a.date, n.the_geom from
tmp_neue n left join schulweg_neu.routing_aktuell a on a.gid = n.gid where
sub_id > 1;

drop table if exists tmp_inter_loc;
drop table if exists tmp_neue;
drop table if exists tmp_intergeom;