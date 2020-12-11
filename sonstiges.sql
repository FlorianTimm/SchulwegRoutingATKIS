

-- dichte Knoten aus pgr_analyzeGraph
with
buffer AS (select id, st_buffer(the_geom,0.01) AS buff FROM schulweg_neu.routing_aktuell_vertices_pgr WHERE cnt=1),
veryclose AS (
	select b.id, st_crosses(a.the_geom,b.buff) AS flag FROM
	(select * FROM schulweg_neu.routing_aktuell WHERE true) AS a
	join buffer AS b on (a.the_geom&&b.buff) WHERE source != b.id AND target != b.id )
UPDATE schulweg_neu.routing_aktuell_vertices_pgr 
set chk=1 WHERE id IN (select distinct id FROM veryclose WHERE flag=true)
