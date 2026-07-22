// Requête de STAGING — désactiver "Activer le chargement" (clic droit > Activer le chargement)
// Elle centralise : l'appel API, l'aplatissement JSON, et l'anti-doublon (5 clés + id max).
// Les requêtes "Production" et "Arrets" référencent toutes les deux cette requête.
let
    // Ne JAMAIS committer le token en clair dans un fichier source versionné.
    // Dans Power BI : Transformer les données > Gérer les paramètres > créer un paramètre texte "Bearer_Token"
    // et le renseigner via les informations d'identification (ou un paramètre chiffré côté service).
    Bearer_Token = Bearer_Token, // paramètre Power Query de type texte

    Source = Json.Document(Web.Contents(
        "https://gate.teeptrak.net/api/v1/external/hutchinson_custom_ones.json?power_bi=true",
        [Headers = [Authorization = "Bearer " & Bearer_Token]]
    )),
    data = Source[data],
    #"Converti en table" = Table.FromList(data, Splitter.SplitByNothing(), null, null, ExtraValues.Error),

    #"Colonne1 développée" = Table.ExpandRecordColumn(#"Converti en table", "Column1",
        {"id", "created_at", "updated_at", "started_at", "ended_at", "factory_id", "shift_data"},
        {"id", "created_at", "updated_at", "started_at", "ended_at", "factory_id", "shift_data"}),

    // Un seul niveau de liste à éclater : shift_data. Tout le reste en dessous est du Record,
    // donc Table.ExpandRecordColumn ne multiplie PAS les lignes (c'est important : la source
    // de "trop de lignes" n'est jamais l'expand de issue_type_durations en colonnes, c'est
    // uniquement cet éclatement de liste-ci).
    #"shift_data éclaté" = Table.ExpandListColumn(#"Colonne1 développée", "shift_data"),
    #"shift_data développé" = Table.ExpandRecordColumn(#"shift_data éclaté", "shift_data",
        {"shift_start_date", "factory_name", "workshop_name", "machine_name", "machine_id", "shift_key",
         "product_name", "net_count", "good_count", "bad_count", "productive_duration",
         "issue_type_durations", "product_custom_reference"},
        {"shift_start_date", "factory_name", "workshop_name", "machine_name", "machine_id", "shift_key",
         "product_name", "net_count", "good_count", "bad_count", "productive_duration",
         "issue_type_durations", "product_custom_reference"}),

    // Typage minimal requis pour construire la clé et trier par id
    #"Types clé" = Table.TransformColumnTypes(#"shift_data développé", {
        {"id", Int64.Type},
        {"shift_start_date", type date}
    }),

    // Renommage des 5 dimensions utilisées par la clé (repris ensuite par Production et Arrets)
    #"Colonnes renommées" = Table.RenameColumns(#"Types clé", {
        {"shift_start_date", "Date de Production"},
        {"shift_key", "Equipe"},
        {"machine_name", "Machine"},
        {"workshop_name", "Atelier"},
        {"product_name", "Produit"}
    }),

    // Exclusion des autoclaves (repris de la requête d'origine)
    #"Lignes filtrées" = Table.SelectRows(#"Colonnes renommées",
        each [Machine] <> "PL_Autoclave 1" and [Machine] <> "PL_Autoclave 2" and [Machine] <> "PL_Autoclave 3"),

    // Clé métier : les 5 clés demandées (Date + Equipe + Machine + Atelier + Produit)
    #"Ajout Clé" = Table.AddColumn(#"Lignes filtrées", "Cle_5", each
        Date.ToText([Date de Production], "yyyy-MM-dd") & "|" &
        Text.From([Equipe]) & "|" &
        Text.From([Machine]) & "|" &
        Text.From([Atelier]) & "|" &
        Text.From([Produit]),
    type text),

    // Anti-doublon : pour chaque clé identique, on ne garde que la ligne avec l'id le plus grand
    #"Groupé par clé" = Table.Group(#"Ajout Clé", {"Cle_5"}, {
        {"Ligne", each Table.FirstN(Table.Sort(_, {{"id", Order.Descending}}), 1)}
    }),
    #"Déplié" = Table.ExpandTableColumn(#"Groupé par clé", "Ligne", Table.ColumnNames(#"Ajout Clé")),
    #"Suppression Clé technique" = Table.RemoveColumns(#"Déplié", {"Cle_5"})
in
    #"Suppression Clé technique"
