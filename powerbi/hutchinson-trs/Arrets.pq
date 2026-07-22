// Table ARRETS : format LONG (une ligne par arrêt de production), pas un mur de colonnes.
// On "développe jusqu'à shift_key" (id / date / atelier / machine / équipe) puis on
// concatène tous les types d'arrêt de issue_type_durations en lignes via Record.ToTable,
// au lieu de les développer un par un en colonnes (ce qui casse dès que Teeptrak ajoute
// une nouvelle cause d'arrêt, et ne donne pas un format exploitable en DAX/waterfall).
let
    Source = Base,

    #"Colonnes gardées" = Table.SelectColumns(Source,
        {"id", "Date de Production", "factory_name", "Atelier", "Machine", "machine_id", "Equipe", "issue_type_durations"}),

    // On ne garde que les catégories de 1er niveau (Arrêts planifiés, Pannes, Réglages, ...)
    // et pas leur éclatement "_details" par sous-cause : ce sont ces "_details" imbriqués
    // qui produisaient les dizaines de colonnes dans la requête d'origine.
    #"Catégories 1er niveau" = Table.AddColumn(#"Colonnes gardées", "Categories", each
        Record.SelectFields(
            [issue_type_durations],
            List.Select(Record.FieldNames([issue_type_durations]), each not Text.Contains(_, "_details")),
            MissingField.Ignore
        )
    ),
    #"Colonnes supprimées" = Table.RemoveColumns(#"Catégories 1er niveau", {"issue_type_durations"}),

    // Record.ToTable transforme le record {NomCatégorie -> {duration, occurrences, ...}}
    // en une mini-table {Name, Value} : c'est ça qui permet de "concaténer" tous les types
    // d'arrêt d'une même ligne en plusieurs lignes, proprement, sans expand automatique.
    #"Ajout table catégories" = Table.AddColumn(#"Colonnes supprimées", "CategoriesTable", each Record.ToTable([Categories])),
    #"Colonnes supprimées 2" = Table.RemoveColumns(#"Ajout table catégories", {"Categories"}),
    #"Déplié CategoriesTable" = Table.ExpandTableColumn(#"Colonnes supprimées 2", "CategoriesTable",
        {"Name", "Value"}, {"Type Arret", "Detail"}),

    // Une ligne par type d'arrêt réellement présent sur le poste (pas de ligne vide pour
    // les catégories absentes de ce shift)
    #"Lignes filtrées" = Table.SelectRows(#"Déplié CategoriesTable", each [Detail] <> null),

    #"Déplié Detail" = Table.ExpandRecordColumn(#"Lignes filtrées", "Detail",
        {"duration", "occurrences", "loss_level0_id", "loss_level0_name"},
        {"Duree Arret (s)", "Occurrences", "Loss Level0 Id", "Loss Level0 Name"}),

    #"Types changés" = Table.TransformColumnTypes(#"Déplié Detail", {
        {"Duree Arret (s)", type number},
        {"Occurrences", type number}
    })
in
    #"Types changés"
