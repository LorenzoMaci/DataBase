-- Progetto Basi di Dati - Traccia 118: gestione del prestito di strumenti da cantiere
-- Lorenzo Maci, 1000031651

DROP DATABASE IF EXISTS prestito_strumenti_cantiere;
CREATE DATABASE prestito_strumenti_cantiere CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE prestito_strumenti_cantiere;

-- CREAZIONE TABELLE

CREATE TABLE DIPENDENTE (
    id_dipendente INT NOT NULL AUTO_INCREMENT,
    nome VARCHAR(50) NOT NULL,
    cognome VARCHAR(50) NOT NULL,
    ruolo VARCHAR(50) NOT NULL,
    telefono VARCHAR(20),
    email VARCHAR(100) NOT NULL,
    PRIMARY KEY(id_dipendente),
    CONSTRAINT dipendente_email UNIQUE (email) -- due dipendenti non possono avere la stessa email
);

CREATE TABLE CANTIERE (
    id_cantiere INT NOT NULL AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL,
    indirizzo VARCHAR(200) NOT NULL,
    data_inizio DATE NOT NULL,
    data_fine DATE,
    dipendente_responsabile INT NOT NULL, -- responsabile del cantiere
    PRIMARY KEY(id_cantiere),
    CONSTRAINT check_cantiere_data CHECK (data_fine IS NULL OR data_fine >= data_inizio), -- la fine non precede l'inizio
    FOREIGN KEY (dipendente_responsabile) REFERENCES DIPENDENTE(id_dipendente)
    ON DELETE RESTRICT ON UPDATE RESTRICT
);

-- Dizionario dei quattro stati dello strumento: STRUMENTO ne salva solo il codice.
CREATE TABLE STATO (
    id_stato INT NOT NULL,
    descrizione VARCHAR(30) NOT NULL,
    PRIMARY KEY(id_stato),
    CONSTRAINT uq_stato_descrizione UNIQUE (descrizione) -- due stati non possono avere la stessa descrizione
);

INSERT INTO STATO (id_stato, descrizione) VALUES
    (1,'disponibile'),
    (2,'in prestito'),
    (3,'in manutenzione'),
    (4,'danneggiato');

CREATE TABLE STRUMENTO (
    id_strumento INT NOT NULL AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL,
    categoria VARCHAR(50) NOT NULL,
    scheda_tecnica TEXT,
    data_acquisto DATE NOT NULL,
    stato INT NOT NULL DEFAULT 1, -- codice di STATO; uno strumento nuovo è disponibile
    PRIMARY KEY(id_strumento),
    FOREIGN KEY (stato) REFERENCES STATO(id_stato)
        ON DELETE RESTRICT ON UPDATE RESTRICT, -- lo stato è uno dei quattro dichiarati nel dizionario
    KEY idx_strumento_nome (nome) -- ricerca per nome (O7a)
);


CREATE TABLE PRESTITO (
    id_prestito INT NOT NULL AUTO_INCREMENT,
    strumento INT NOT NULL,
    cantiere INT NOT NULL,
    dipendente_prestatario INT NOT NULL,
    data_uscita DATE NOT NULL,
    data_ritorno_previsionale DATE NOT NULL,
    data_ritorno_effettivo DATE,
    condizione_ritorno VARCHAR(20),
    aperto INT GENERATED ALWAYS AS (IF(data_ritorno_effettivo IS NULL, strumento, NULL)) VIRTUAL, -- vale lo strumento se il prestito è aperto, NULL se è chiuso
    PRIMARY KEY(id_prestito),
    CONSTRAINT check_prestito_ritorno_prev CHECK (data_ritorno_previsionale >= data_uscita),
    CONSTRAINT check_prestito_ritorno_eff CHECK (data_ritorno_effettivo IS NULL OR data_ritorno_effettivo >= data_uscita),
    CONSTRAINT check_prestito_condizione CHECK (condizione_ritorno IS NULL OR condizione_ritorno IN ('buona','usurata','danneggiata')),
    FOREIGN KEY (strumento) REFERENCES STRUMENTO(id_strumento)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (cantiere) REFERENCES CANTIERE(id_cantiere)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (dipendente_prestatario) REFERENCES DIPENDENTE(id_dipendente)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT uq_prestito_aperto UNIQUE (aperto), -- al massimo un prestito aperto per strumento
    KEY idx_prestito_strumento (strumento, data_ritorno_effettivo), --  indice sui prestiti di uno strumento O9 e controlli dei trigger
    KEY idx_prestito_cantiere (cantiere, data_ritorno_effettivo) -- indice sui prestiti di un cantiere  O8, O12
);

CREATE TABLE MANUTENZIONE (
    id_manutenzione INT NOT NULL AUTO_INCREMENT,
    strumento INT NOT NULL,
    dipendente_esecutore INT NOT NULL, -- dipendente che ha eseguito l'intervento
    data DATE NOT NULL,
    tipo VARCHAR(30) NOT NULL,
    costo DECIMAL(10,2) NOT NULL DEFAULT 0,
    descrizione TEXT,
    PRIMARY KEY(id_manutenzione),
    CONSTRAINT check_manutenzione_tipo CHECK (tipo IN ('controllo_sicurezza','riparazione','tagliando')),
    CONSTRAINT check_manutenzione_costo CHECK (costo >= 0),
    FOREIGN KEY (strumento) REFERENCES STRUMENTO(id_strumento)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (dipendente_esecutore) REFERENCES DIPENDENTE(id_dipendente)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    KEY idx_manutenzione_strumento (strumento, data, costo) -- indice per i costi totali delle manutenzioni per strumento e per anno (O10)
);

-- Stato del prestito (in_uso, restituito, danneggiato), calcolato e non memorizzato.
CREATE VIEW v_prestito AS
SELECT id_prestito, strumento, cantiere, dipendente_prestatario,
       data_uscita, data_ritorno_previsionale, data_ritorno_effettivo, condizione_ritorno,
       CASE WHEN data_ritorno_effettivo IS NULL THEN 'in_uso'
            WHEN condizione_ritorno = 'danneggiata' THEN 'danneggiato'
            ELSE 'restituito'
       END AS stato_prestito
FROM PRESTITO;

-- TRIGGER

-- Nuovo prestito: lo strumento non deve avere un prestito aperto e deve essere disponibile.
DELIMITER //
CREATE TRIGGER prestito_doppio
BEFORE INSERT ON PRESTITO
FOR EACH ROW
BEGIN
    DECLARE prestiti_aperti INT;
    DECLARE stato_strumento INT;

    IF NEW.data_ritorno_effettivo IS NULL THEN
        SELECT COUNT(*) INTO prestiti_aperti
        FROM PRESTITO
        WHERE strumento = NEW.strumento AND data_ritorno_effettivo IS NULL;

        IF prestiti_aperti > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =  'Strumento già in prestito';
        END IF;

        SELECT stato INTO stato_strumento
        FROM STRUMENTO
        WHERE id_strumento = NEW.strumento;

        IF stato_strumento <> 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =  'Strumento non disponibile per il prestito';
        END IF;

    ELSE
        IF NEW.condizione_ritorno IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Non è stata fornita alcuna condizione_ritorno';
        END IF;

    END IF;
END;
//
DELIMITER ;


-- Modifica di un prestito: lo strumento non si cambia e un prestito chiuso non si riapre.
DELIMITER //
CREATE TRIGGER storico_prestito
BEFORE UPDATE ON PRESTITO
FOR EACH ROW
BEGIN
    DECLARE prestiti_aperti INT;

    IF NEW.strumento <> OLD.strumento THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'strumento di un prestito non modificabile';
        END IF;

    IF NEW.data_ritorno_effettivo IS NULL THEN
        SELECT COUNT(*) INTO prestiti_aperti
        FROM PRESTITO
        WHERE strumento = NEW.strumento
            AND data_ritorno_effettivo IS NULL
            AND id_prestito <> OLD.id_prestito;

        IF prestiti_aperti > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Strumento già in prestito';
        END IF;

        -- la proroga di un prestito aperto è ammessa, la riapertura di uno chiuso no
        IF OLD.data_ritorno_effettivo IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prestito già chiuso: la riapertura non è ammessa, lo storico non è modificabile';
        END IF;
    ELSE
        IF NEW.condizione_ritorno IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Non è stata fornita alcuna condizione_ritorno';
        END IF;

    END IF;
END;
//
DELIMITER ;


-- Aggiorna lo stato dello strumento quando si inserisce un prestito: in prestito se è aperto,
-- danneggiato se è già chiuso in quella condizione ed è l'ultimo rientro dello strumento.
DELIMITER //
CREATE TRIGGER stato_strumento_uscita
AFTER INSERT ON PRESTITO
FOR EACH ROW
BEGIN
    IF NEW.data_ritorno_effettivo IS NULL THEN
        UPDATE STRUMENTO SET stato = 2 -- in prestito
        WHERE id_strumento = NEW.strumento;

    ELSEIF NEW.condizione_ritorno = 'danneggiata' AND NOT EXISTS (
        SELECT 1
        FROM PRESTITO p2
        WHERE p2.strumento = NEW.strumento
            AND p2.id_prestito <> NEW.id_prestito
            AND (p2.data_ritorno_effettivo IS NULL
                OR p2.data_ritorno_effettivo > NEW.data_ritorno_effettivo
                OR (p2.data_ritorno_effettivo = NEW.data_ritorno_effettivo AND p2.id_prestito > NEW.id_prestito))
    ) THEN
        UPDATE STRUMENTO SET stato = 4 -- danneggiato
        WHERE id_strumento = NEW.strumento AND stato = 1;
    END IF;
END;
//
DELIMITER ;


-- Aggiorna lo stato dello strumento quando un prestito viene prorogato, chiuso o corretto.
DELIMITER //
CREATE TRIGGER stato_strumento_rientro
AFTER UPDATE ON PRESTITO
FOR EACH ROW
BEGIN
    IF NEW.data_ritorno_effettivo IS NULL THEN
        UPDATE STRUMENTO SET stato = 2 -- in prestito
        WHERE id_strumento = NEW.strumento;

    ELSEIF OLD.data_ritorno_effettivo IS NULL THEN
        UPDATE STRUMENTO
        SET stato = IF(NEW.condizione_ritorno = 'danneggiata',4,1) -- 4 danneggiato o 1 disponibile
        WHERE id_strumento = NEW.strumento;

    ELSEIF NEW.condizione_ritorno <> OLD.condizione_ritorno THEN
        -- correzione della condizione: vale solo se è l'ultimo rientro dello strumento
        IF NOT EXISTS (
            SELECT 1
            FROM PRESTITO p2
            WHERE p2.strumento = NEW.strumento
                AND p2.id_prestito <> NEW.id_prestito
                AND (p2.data_ritorno_effettivo IS NULL
                    OR p2.data_ritorno_effettivo > NEW.data_ritorno_effettivo
                    OR (p2.data_ritorno_effettivo = NEW.data_ritorno_effettivo AND p2.id_prestito > NEW.id_prestito))
        ) THEN
            IF NEW.condizione_ritorno = 'danneggiata' THEN
                UPDATE STRUMENTO SET stato = 4 -- danneggiato
                WHERE id_strumento = NEW.strumento AND stato = 1;

            ELSEIF OLD.condizione_ritorno = 'danneggiata' THEN
                UPDATE STRUMENTO SET stato = 1 -- disponibile
                WHERE id_strumento = NEW.strumento AND stato = 4;
            END IF;
        END IF;
    END IF;
END;
//
DELIMITER ;


-- Nuova riparazione: rifiutata se lo strumento è in prestito o già in manutenzione.
DELIMITER //
CREATE TRIGGER nuova_manutenzione
BEFORE INSERT ON MANUTENZIONE
FOR EACH ROW
BEGIN
    DECLARE stato_strumento INT;

    IF NEW.tipo = 'riparazione' THEN
        SELECT stato INTO stato_strumento
        FROM STRUMENTO
        WHERE id_strumento = NEW.strumento;

        IF stato_strumento = 2 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Richiesta riparazione su uno strumento già in prestito';
        END IF;

        IF stato_strumento = 3 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Riparazione già aperta sullo strumento';
        END IF;
    END IF;
END;
//
DELIMITER ;


-- Una riparazione porta lo strumento in manutenzione; controlli e tagliandi non cambiano lo stato.
DELIMITER //
CREATE TRIGGER stato_strumento_manutenzione
AFTER INSERT ON MANUTENZIONE
FOR EACH ROW
BEGIN
    IF NEW.tipo = 'riparazione' THEN
        UPDATE STRUMENTO SET stato = 3 -- in manutenzione
        WHERE id_strumento = NEW.strumento;
    END IF;
END;
//
DELIMITER ;

-- Una manutenzione registrata non si modifica.
DELIMITER //
CREATE TRIGGER blocca_modifica_manutenzione
BEFORE UPDATE ON MANUTENZIONE
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manutenzione non modificabile: gli interventi registrati fanno parte dello storico';
END;
//
DELIMITER ;

-- Prestiti e manutenzioni sono lo storico: le loro righe non si cancellano.
DELIMITER //
CREATE TRIGGER cancellazione_prestito
BEFORE DELETE ON PRESTITO
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancellazione del prestito non ammessa perché lo storico non è modificabile';
END;
//
DELIMITER ;

DELIMITER //
CREATE TRIGGER cancellazione_manutenzione
BEFORE DELETE ON MANUTENZIONE
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancellazione della Manutenzione non ammessa perché lo storico non è modificabile';
END;
//
DELIMITER ;

-- Le righe del dizionario STATO non si modificano e non si cancellano.
DELIMITER //
CREATE TRIGGER modifica_stato
BEFORE UPDATE ON STATO
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Descrizione di uno stato non modificabile: i valori del dizionario sono fissi';
END;
//
DELIMITER ;

DELIMITER //
CREATE TRIGGER cancellazione_stato
BEFORE DELETE ON STATO
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancellazione di uno stato non ammessa: il dizionario dei valori è fisso';
END;
//
DELIMITER ;

-- INSERIMENTO DATI DI ESEMPIO
-- Lo stato degli strumenti non si inserisce: lo scrivono i trigger.

INSERT INTO DIPENDENTE (nome, cognome, ruolo, telefono, email) VALUES
    ('Marco','Rossi','capocantiere','091-555101','m.rossi@edile.example'),
    ('Luca','Bianchi','capocantiere','091-555102','l.bianchi@edile.example'),
    ('Anna','Verdi','capocantiere','091-555103','a.verdi@edile.example'),
    ('Giuseppe','Esposito','operaio','091-555104','g.esposito@edile.example'),
    ('Antonio','Ricci','operaio','091-555105','a.ricci@edile.example'),
    ('Francesco','Gallo','operaio','091-555106','f.gallo@edile.example'),
    ('Davide','Conti','operaio','091-555107','d.conti@edile.example'),
    ('Stefano','Marino','operaio','091-555108','s.marino@edile.example'),
    ('Roberto','Greco','tecnico manutentore','091-555109','r.greco@edile.example'),
    ('Paolo','Bruno','tecnico manutentore','091-555110','p.bruno@edile.example'),
    ('Elisa','Costa','impiegato ufficio prestiti','091-555111','e.costa@edile.example'),
    ('Sara','Ianni','impiegato ufficio prestiti','091-555112','s.ianni@edile.example');

INSERT INTO CANTIERE (nome, indirizzo, data_inizio, data_fine, dipendente_responsabile) VALUES
    ('Residenza Belvedere','Via Roma 12, Palermo','2026-01-12',NULL,1),
    ('Ristrutturazione Scuola Manzoni','Corso Calatafimi 88, Palermo','2026-03-02',NULL,2),
    ('Ponte sul Fiume Oreto','SS121 km 5, Palermo','2026-05-18',NULL,3),
    ('Palazzina Via Libertà','Via Libertà 45, Palermo','2025-09-01','2026-06-30',1),
    ('Ampliamento Polo Logistico','Z.I. Brancifanti, Palermo','2026-08-03',NULL,2);

INSERT INTO STRUMENTO (nome, categoria, scheda_tecnica, data_acquisto) VALUES
    ('Trapano a percussione Hilti TE-30','elettrico','800 W, attacco SDS-Plus, 3.3 kg','2024-03-10'),
    ('Martello demolitore Hilti TE 1000-AVR','elettrico','1900 W, riduzione vibrazioni AVR','2023-06-22'),
    ('Saldatrice inverter Telwin Force 165','saldatura','elettrodi fino a 4 mm','2025-01-15'),
    ('Betoniera a bicchiere Imer Syntesi 250','betonaggio','vasca 250 L, motore elettrico monofase','2024-09-05'),
    ('Gruppo elettrogeno Honda EU70is','elettrico','7 kVA, inverter, benzina','2022-11-30'),
    ('Compressore a cinghia Fiac AB 500','pneumatico','serbatoio 500 L, 10 bar','2023-02-18'),
    ('Troncatrice a disco Husqvarna K770','taglio','disco 350 mm, motore a scoppio','2024-07-01'),
    ('Montacarichi a cavalletto 200 kg','sollevamento','argano elettrico, portata 200 kg','2021-04-12'),
    ('Piastra vibrante Wacker Neuson WP 1550','vibrante','piastra reversibile, circa 90 kg','2025-03-20'),
    ('Mescolatore per malta Collomix Xo 55','posa','mescolatore elettrico a doppia frusta','2022-08-08'),
    ('Scala a sfilo in alluminio Faraone 12 m','sollevamento','alluminio, due rampe, 12 m','2023-10-27'),
    ('Cesoia a batteria Milwaukee M12 BMS12','taglio','batteria 12 V, per lamiera','2026-02-14'),
    ('Scalpellatore Hilti TE 500-AVR','elettrico','Active Vibration Reduction (AVR)','2024-01-09'),
    ('Motopompa Honda WT30','idraulico','pompa per acque cariche da 3 pollici','2020-05-19'),
    ('Rullo vibrante tandem Ammann ARX 26','vibrante','rullo tandem vibrante articolato','2025-11-11');

-- Prestiti di esempio: sei chiusi, tre in corso entro la scadenza, uno scaduto e mai restituito.
INSERT INTO PRESTITO (strumento, cantiere, dipendente_prestatario, data_uscita, data_ritorno_previsionale, data_ritorno_effettivo, condizione_ritorno) VALUES
    (1, 1, 4, '2026-08-03','2026-08-10','2026-08-09','buona'), -- chiuso, buona
    (1, 2, 5, '2026-09-01','2026-09-08','2026-09-10','usurata'), -- chiuso, usurata
    (2, 1, 6, '2026-06-15','2026-06-22','2026-06-20','danneggiata'), -- chiuso, riparazione conclusa
    (11, 4, 7, '2026-04-01','2026-04-08','2026-04-07','buona'), -- chiuso, buona
    (7, 1, 7, '2026-09-14','2026-09-21','2026-09-25','buona'), -- chiuso in ritardo
    (12, 1, 8, '2026-09-20','2026-09-27','2026-09-26','danneggiata'), -- danneggiato, non ancora riparato
    (3, 3, 8, '2026-09-28','2026-10-12',NULL,NULL), -- in corso
    (4, 5, 4, '2026-10-01','2026-10-15',NULL,NULL), -- in corso
    (5, 2, 5, '2026-09-30','2026-10-14',NULL,NULL), -- in corso
    (6, 3, 6, '2026-09-05','2026-09-12',NULL,NULL); -- scaduto, mai restituito

-- Manutenzioni di esempio: controlli, tagliandi e tre riparazioni già concluse.
INSERT INTO MANUTENZIONE (strumento, dipendente_esecutore, data, tipo, costo, descrizione) VALUES
    (2, 9 ,'2026-06-25','riparazione',320.00,'Sostituzione mazza e grasso dopo ritorno danneggiato'),
    (2, 10,'2026-07-01','controllo_sicurezza',0.00,'Controllo di sicurezza dopo la riparazione'),
    (1, 10,'2026-09-12','tagliando',85.00,'Tagliando periodico 12 mesi'),
    (11, 9 ,'2026-03-15','controllo_sicurezza',0.00,'Controllo periodico scala a sfilo'),
    (8, 9 ,'2026-02-20','riparazione',210.00,'Riparazione argano montacarichi'),
    (8, 10,'2026-05-05','controllo_sicurezza',0.00,'Collaudo di sicurezza dopo riparazione argano'),
    (10, 9 ,'2025-12-10','riparazione',540.00,'Rottura della frusta, sostituzione frusta e cuscinetti'),
    (10, 10,'2026-01-08','controllo_sicurezza',0.00,'Verifica dopo riparazione mescolatore'),
    (14, 10,'2026-06-01','tagliando',120.00,'Tagliando motopompa (olio, candela)'),
    (15, 9 ,'2026-09-08','controllo_sicurezza',0.00,'Controllo alla prima consegna in cantiere');

-- Chiusura delle tre riparazioni di esempio (strumenti 2, 8, 10), come in O13.
UPDATE STRUMENTO SET stato = 1 -- disponibile
WHERE id_strumento IN (2, 8, 10) AND stato = 3;
