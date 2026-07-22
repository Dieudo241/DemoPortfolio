// Table PRODUCTION : une ligne par (Date, Equipe, Machine, Atelier, Produit) dédupliquée,
// sans les colonnes d'arrêts (portées par la table "Arrets").
let
    Source = Base,
    #"Colonnes supprimées" = Table.RemoveColumns(Source, {"issue_type_durations"}),
    #"Colonnes renommées" = Table.RenameColumns(#"Colonnes supprimées", {
        {"net_count", "Quantité Nette"},
        {"good_count", "Quantité Conforme"},
        {"bad_count", "Quantité Rebut"},
        {"productive_duration", "Temps Productif (s)"}
    }),
    #"Types changés" = Table.TransformColumnTypes(#"Colonnes renommées", {
        {"Quantité Nette", type number},
        {"Quantité Conforme", type number},
        {"Quantité Rebut", type number},
        {"Temps Productif (s)", type number},
        {"created_at", type datetime},
        {"updated_at", type datetime},
        {"started_at", type datetime},
        {"ended_at", type datetime}
    })
in
    #"Types changés"
