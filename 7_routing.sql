
delete from schulweg_neu.routing_aktuell where not st_isvalid(the_geom) or st_length(the_geom) < 1;

DROP TABLE IF EXISTS schulweg_neu.routing_aktuell_vertices_pgr;
SELECT  pgr_createTopology('schulweg_neu.routing_aktuell', 0.1,'the_geom', 'gid', 'source', 'target');
CREATE INDEX IF NOT EXISTS routing_aktuell_vertices_pgr_the_geom
    ON schulweg_neu.routing_aktuell_vertices_pgr USING gist
    (the_geom);
--VACUUM FULL ANALYZE schulweg_neu.routing_aktuell;
--VACUUM FULL ANALYZE schulweg_neu.routing_aktuell_vertices_pgr;

SELECT  pgr_analyzeGraph('schulweg_neu.routing_aktuell',3,'the_geom','gid','source','target');

