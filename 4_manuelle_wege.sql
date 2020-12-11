insert into schulweg_neu.routing_aktuell (gewicht, bwf, the_geom)
select 2 gewicht, 0 bwf, the_geom from schulweg_neu.bsb_wege;