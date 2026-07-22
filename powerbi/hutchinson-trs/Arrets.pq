// Table ARRETS — requête autonome (aucune dépendance à une autre requête).
// Format LONG : une ligne par (id, Type Arret) au lieu d'une colonne par type
// d'arrêt / sous-cause. On applique le MÊME anti-doublon que côté Production
// (5 clés, id max) AVANT d'éclater issue_type_durations, pour dédupliquer au
// niveau du poste et non au niveau de chaque ligne d'arrêt.
let
    // Même paramètre "Bearer_Token" que dans Production.pq
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

    #"shift_data éclaté" = Table.ExpandListColumn(#"Colonne1 développée", "shift_data"),
    #"shift_data développé" = Table.ExpandRecordColumn(#"shift_data éclaté", "shift_data",
        {"shift_start_date", "factory_name", "workshop_name", "machine_name", "machine_id", "shift_key",
         "product_name", "net_count", "good_count", "bad_count", "productive_duration",
         "issue_type_durations", "product_custom_reference"},
        {"shift_start_date", "factory_name", "workshop_name", "machine_name", "machine_id", "shift_key",
         "product_name", "net_count", "good_count", "bad_count", "productive_duration",
         "issue_type_durations", "product_custom_reference"}),

    #"Types clé" = Table.TransformColumnTypes(#"shift_data développé", {
        {"id", Int64.Type},
        {"shift_start_date", type date}
    }),

    #"Colonnes renommées" = Table.RenameColumns(#"Types clé", {
        {"shift_start_date", "Date de Production"},
        {"shift_key", "Equipe"},
        {"machine_name", "Machine"},
        {"workshop_name", "Atelier"},
        {"product_name", "Produit"}
    }),

    #"Lignes filtrées Autoclave" = Table.SelectRows(#"Colonnes renommées",
        each [Machine] <> "PL_Autoclave 1" and [Machine] <> "PL_Autoclave 2" and [Machine] <> "PL_Autoclave 3"),

    // ---- Anti-doublon AVANT l'éclatement des arrêts : mêmes 5 clés que Production ----
    #"Ajout Clé" = Table.AddColumn(#"Lignes filtrées Autoclave", "Cle_5", each
        Date.ToText([Date de Production], "yyyy-MM-dd") & "|" &
        Text.From([Equipe]) & "|" &
        Text.From([Machine]) & "|" &
        Text.From([Atelier]) & "|" &
        Text.From([Produit]),
    type text),
    #"Groupé par clé" = Table.Group(#"Ajout Clé", {"Cle_5"}, {
        {"Ligne", each Table.FirstN(Table.Sort(_, {{"id", Order.Descending}}), 1)}
    }),
    #"Déplié" = Table.ExpandTableColumn(#"Groupé par clé", "Ligne", List.RemoveItems(Table.ColumnNames(#"Ajout Clé"), {"Cle_5"})),
    #"Suppression Clé technique" = Table.RemoveColumns(#"Déplié", {"Cle_5"}),

    // ---- On développe jusqu'à l'équipe (shift_key), puis on ne garde que issue_type_durations ----
    #"Colonnes gardées" = Table.SelectColumns(#"Suppression Clé technique",
        {"id", "Date de Production", "factory_name", "Atelier", "Machine", "machine_id", "Equipe", "issue_type_durations"}),

    // ---- Catégories de 1er niveau uniquement (sans le détail "_details" par sous-cause) ----
    #"Catégories 1er niveau" = Table.AddColumn(#"Colonnes gardées", "Categories", each
        Record.SelectFields(
            [issue_type_durations],
            List.Select(Record.FieldNames([issue_type_durations]), each not Text.Contains(_, "_details")),
            MissingField.Ignore
        )
    ),
    #"Colonnes supprimées Issue" = Table.RemoveColumns(#"Catégories 1er niveau", {"issue_type_durations"}),

    // ---- Concaténation de tous les types d'arrêt en LIGNES (au lieu de colonnes) ----
    #"Ajout table catégories" = Table.AddColumn(#"Colonnes supprimées Issue", "CategoriesTable", each Record.ToTable([Categories])),
    #"Colonnes supprimées Categories" = Table.RemoveColumns(#"Ajout table catégories", {"Categories"}),
    #"Déplié CategoriesTable" = Table.ExpandTableColumn(#"Colonnes supprimées Categories", "CategoriesTable",
        {"Name", "Value"}, {"Type Arret", "Detail"}),

    // Pas de ligne pour les catégories absentes de ce poste
    #"Lignes filtrées Vides" = Table.SelectRows(#"Déplié CategoriesTable", each [Detail] <> null),

    #"Déplié Detail" = Table.ExpandRecordColumn(#"Lignes filtrées Vides", "Detail",
        {"duration", "occurrences", "loss_level0_id", "loss_level0_name"},
        {"Duree Arret (s)", "Occurrences", "Loss Level0 Id", "Loss Level0 Name"}),

    #"Types changés" = Table.TransformColumnTypes(#"Déplié Detail", {
        {"Duree Arret (s)", type number},
        {"Occurrences", type number}
    })
in
    #"Types changés"
