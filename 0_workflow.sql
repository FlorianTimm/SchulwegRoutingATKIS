-- psql -h gv-srv-w00118 -p 5433 -U timm geo < 0_workflow.sql

-- VORHER: ATKIS-Daten mit FME von esri sde -> PostGIS

\i 1_grundnetz.sql
\i 2_bruecken_tunnel.sql
\i 3_plaetze.sql
\i 4_manuelle_wege.sql
\i 5_parks.sql
\i 6_kreuzung.sql
\i 7_routing.sql
\i 8_sackgassen.sql