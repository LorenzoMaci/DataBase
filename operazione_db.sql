-- Operazioni O1-O14. Eseguire dopo creazione_db.sql, una sola volta.
USE prestito_strumenti_cantiere;

-- OPERAZIONI DI SCRITTURA
-- Lo stato degli strumenti lo aggiornano i trigger, tranne in O13.

-- O1: registrazione di un nuovo strumento
INSERT INTO STRUMENTO (nome, categoria, scheda_tecnica, data_acquisto)
    VALUES ('Seghetto alternativo Metabo STEB 65','elettrico','650 W, corsa 26 mm','2026-10-05'); -- stato: DEFAULT 1 (disponibile)

-- O2: apertura di un nuovo cantiere
INSERT INTO CANTIERE (nome, indirizzo, data_inizio, dipendente_responsabile)
    VALUES ('Nuovo parcheggio scambiatorio','Via Oreto angolo Slalom, Palermo','2026-10-05',3);

-- O3: registrazione di un nuovo dipendente
INSERT INTO DIPENDENTE (nome, cognome, ruolo, telefono, email)
    VALUES ('Katia','Leone','operaio','091-555113','k.leone@edile.example');

-- O4: apertura di un prestito (lo strumento passa in prestito)
INSERT INTO PRESTITO (strumento, cantiere, dipendente_prestatario, data_uscita, data_ritorno_previsionale)
    VALUES (9, 5, 8, '2026-10-05', '2026-10-19');

-- O5: rientro di uno strumento con la sua condizione
UPDATE PRESTITO
SET data_ritorno_effettivo = '2026-10-05', condizione_ritorno = 'usurata'
WHERE id_prestito = 7 AND data_ritorno_effettivo IS NULL; -- prestito aperto dello strumento 3

-- O6: registrazione di una manutenzione
-- (a) controllo di sicurezza: lo stato non cambia
INSERT INTO MANUTENZIONE (strumento, dipendente_esecutore, data, tipo, costo, descrizione)
    VALUES (14, 9, '2026-10-05','controllo_sicurezza',0.00,'Controllo periodico motopompa');

-- (b) riparazione: lo strumento passa in manutenzione
INSERT INTO MANUTENZIONE (strumento, dipendente_esecutore, data, tipo, costo, descrizione)
    VALUES (13, 10, '2026-10-05','riparazione',180.00,'Sostituzione punta e guarnizioni');

-- O13: chiusura di una riparazione, solo se lo strumento è in manutenzione (stato = 3)
UPDATE STRUMENTO SET stato = 1 -- disponibile
WHERE id_strumento = 13 AND stato = 3;


-- OPERAZIONI DI LETTURA

-- O7a: ricerca di uno strumento per nome
SELECT s.id_strumento, s.nome, s.categoria, s.data_acquisto, st.descrizione AS stato
FROM STRUMENTO s
JOIN STATO st ON st.id_stato = s.stato
WHERE s.nome LIKE 'trapano%';

-- O7b: ricerca di uno strumento per categoria
SELECT s.id_strumento, s.nome, s.categoria, s.data_acquisto, st.descrizione AS stato
FROM STRUMENTO s
JOIN STATO st ON st.id_stato = s.stato
WHERE s.categoria = 'sollevamento';

-- O8: prestiti scaduti e mai restituiti di un cantiere (il ritardo dipende dal giorno di esecuzione)
SELECT p.id_prestito, s.nome AS n_strumento, c.nome AS n_cantiere, d.nome, d.cognome, p.data_uscita, p.data_ritorno_previsionale, DATEDIFF(CURDATE(), p.data_ritorno_previsionale) AS giorni_ritardo
FROM PRESTITO p
JOIN STRUMENTO s ON s.id_strumento = p.strumento
JOIN CANTIERE c ON c.id_cantiere = p.cantiere
JOIN DIPENDENTE d ON d.id_dipendente = p.dipendente_prestatario
WHERE p.cantiere = 3 -- cantiere di esempio
  AND p.data_ritorno_effettivo IS NULL
  AND p.data_ritorno_previsionale < CURDATE()
ORDER BY p.data_ritorno_previsionale;

-- O9: storico di utilizzo di uno strumento
SELECT s.id_strumento, s.nome, COUNT(p.id_prestito) AS n_prestiti, SUM(DATEDIFF(COALESCE(p.data_ritorno_effettivo, CURDATE()), p.data_uscita)) AS giorni_in_prestito
FROM STRUMENTO s
LEFT JOIN PRESTITO p ON p.strumento = s.id_strumento
WHERE s.id_strumento = 1
GROUP BY s.id_strumento, s.nome;

-- O10: costo totale delle manutenzioni per strumento e per anno
SELECT s.id_strumento, s.nome, YEAR(m.data) AS anno, SUM(m.costo) AS costo_manutenzioni
FROM STRUMENTO s
JOIN MANUTENZIONE m ON m.strumento = s.id_strumento
GROUP BY s.id_strumento, s.nome, YEAR(m.data);

-- O11: strumenti danneggiati e non ancora riparati
SELECT s.id_strumento, s.nome, s.categoria, s.data_acquisto, st.descrizione AS stato
FROM STRUMENTO s
JOIN STATO st ON st.id_stato = s.stato
WHERE s.stato = 4;

-- O12: strumenti in prestito per ogni cantiere aperto
SELECT c.id_cantiere, c.nome AS cantiere, COUNT(p.id_prestito) AS strumenti_in_prestito
FROM CANTIERE c
LEFT JOIN PRESTITO p ON p.cantiere = c.id_cantiere AND p.data_ritorno_effettivo IS NULL
WHERE c.data_fine IS NULL -- solo i cantieri aperti
GROUP BY c.id_cantiere, c.nome;

-- O14: stato di ogni prestito di uno strumento, letto dalla vista v_prestito
SELECT v.id_prestito, s.nome AS strumento, c.nome AS cantiere,
       v.data_uscita, v.data_ritorno_previsionale, v.data_ritorno_effettivo,
       v.condizione_ritorno, v.stato_prestito
FROM v_prestito v
JOIN STRUMENTO s ON s.id_strumento = v.strumento
JOIN CANTIERE c ON c.id_cantiere = v.cantiere
WHERE v.strumento = 1
ORDER BY v.data_uscita;