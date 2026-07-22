// Table PRODUCTION — requête autonome (aucune dépendance à une autre requête).
// Une ligne par (Date, Equipe, Machine, Atelier, Produit), dédupliquée : pour
// chaque combinaison de ces 5 clés, on ne garde que la ligne dont l'id est le
// plus grand (cas où Teeptrak renvoie un enregistrement corrigé sous un id
// différent pour le même poste).
let
    // Créer un paramètre Power Query de type texte nommé "Bearer_Token"
    // (Accueil > Gérer les paramètres > Nouveau) et y coller le token.
    // Ne jamais coder le token en dur ici si ce fichier est versionné/partagé.
    Bearer_Token = Bearer_Token,

    Source = Json.Document(Web.Contents(
        "https://gate.teeptrak.net/api/v1/external/hutchinson_custom_ones.json?power_bi=true",
        [Headers = [Authorization = "Bearer " & Bearer_Token]]
    )),
    data = Source[data],
    #"Converti en table" = Table.FromList(data, Splitter.SplitByNothing(), null, null, ExtraValues.Error),

    #"Colonne1 développée" = Table.ExpandRecordColumn(#"Converti en table", "Column1",
        {"id", "created_at", "updated_at", "started_at", "ended_at", "factory_id", "shift_data"},
        {"id", "created_at", "updated_at", "started_at", "ended_at", "factory_id", "shift_data"}),

    // Seul ce niveau est une Liste à éclater : le reste est du Record, donc
    // ExpandRecordColumn plus bas ne crée AUCUNE ligne supplémentaire.
    #"shift_data éclaté" = Table.ExpandListColumn(#"Colonne1 développée", "shift_data"),
    #"shift_data développé" = Table.ExpandRecordColumn(#"shift_data éclaté", "shift_data",
        {"shift_start_date", "factory_name", "workshop_name", "machine_name", "machine_id", "shift_key",
         "product_name", "net_count", "good_count", "bad_count", "productive_duration",
         "issue_type_durations", "product_custom_reference"},
        {"shift_start_date", "factory_name", "workshop_name", "machine_name", "machine_id", "shift_key",
         "product_name", "net_count", "good_count", "bad_count", "productive_duration",
         "issue_type_durations", "product_custom_reference"}),

    // Les arrêts vivent dans la table "Arrets" : ici on n'en a pas besoin
    #"Colonnes supprimées Issue" = Table.RemoveColumns(#"shift_data développé", {"issue_type_durations"}),

    #"Types clé" = Table.TransformColumnTypes(#"Colonnes supprimées Issue", {
        {"id", Int64.Type},
        {"shift_start_date", type date}
    }),

    #"Colonnes renommées" = Table.RenameColumns(#"Types clé", {
        {"shift_start_date", "Date de Production"},
        {"shift_key", "Equipe"},
        {"machine_name", "Machine"},
        {"workshop_name", "Atelier"},
        {"product_name", "Produit"},
        {"net_count", "Quantité Nette"},
        {"good_count", "Quantité Conforme"},
        {"bad_count", "Quantité Rebut"},
        {"productive_duration", "Temps Productif (s)"}
    }),

    #"Lignes filtrées Autoclave" = Table.SelectRows(#"Colonnes renommées",
        each [Machine] <> "PL_Autoclave 1" and [Machine] <> "PL_Autoclave 2" and [Machine] <> "PL_Autoclave 3"),

    // ---- Clé anti-doublon : les 5 clés demandées ----
    #"Ajout Clé" = Table.AddColumn(#"Lignes filtrées Autoclave", "Cle_5", each
        Date.ToText([Date de Production], "yyyy-MM-dd") & "|" &
        Text.From([Equipe]) & "|" &
        Text.From([Machine]) & "|" &
        Text.From([Atelier]) & "|" &
        Text.From([Produit]),
    type text),

    // ---- Pour chaque clé en doublon, on ne garde que la ligne avec l'id le plus grand ----
    #"Groupé par clé" = Table.Group(#"Ajout Clé", {"Cle_5"}, {
        {"Ligne", each Table.FirstN(Table.Sort(_, {{"id", Order.Descending}}), 1)}
    }),
    #"Déplié" = Table.ExpandTableColumn(#"Groupé par clé", "Ligne", List.RemoveItems(Table.ColumnNames(#"Ajout Clé"), {"Cle_5"})),
    #"Suppression Clé technique" = Table.RemoveColumns(#"Déplié", {"Cle_5"}),

    #"Types changés" = Table.TransformColumnTypes(#"Suppression Clé technique", {
        {"Quantité Nette", type number},
        {"Quantité Conforme", type number},
        {"Quantité Rebut", type number},
        {"Temps Productif (s)", type number},
        {"created_at", type datetime},
        {"updated_at", type datetime},
        {"started_at", type datetime},
        {"ended_at", type datetime}
    }),

    // ---- Sécurisation : l'API renvoie parfois une erreur (division par zéro /
    // valeur non calculable côté Teeptrak, ex. pseudo-postes de fermeture) au lieu
    // d'un nombre sur ces champs. On neutralise en 0 pour ne pas casser le DAX.
    #"Erreurs Nombres Remplacées" = Table.ReplaceErrorValues(#"Types changés", {
        {"Quantité Nette", 0},
        {"Quantité Conforme", 0},
        {"Quantité Rebut", 0},
        {"Temps Productif (s)", 0}
    })
in
    #"Erreurs Nombres Remplacées"
