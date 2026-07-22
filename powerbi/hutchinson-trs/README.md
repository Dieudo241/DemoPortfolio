# Teeptrak → Power BI : TRS Hutchinson

Refonte de la requête Power Query d'origine (une seule table géante, tous les
sous-détails d'arrêt développés en colonnes) en **2 requêtes M autonomes**,
chacune avec sa propre logique anti-doublon sur les 5 clés métier.

## Pourquoi ce découpage

L'API Teeptrak peut renvoyer un enregistrement corrigé pour un même
(Date, Équipe, Machine, Atelier, Produit) sous un nouvel `id`. Sans clé de
dédoublonnage, ces mises à jour s'additionnent en double dans les totaux.

Développer `issue_type_durations` (et ses `_details` par sous-cause) colonne
par colonne rendait la table très large et cassante à chaque nouvelle cause
d'arrêt ajoutée côté Teeptrak. Le format long (une ligne par type d'arrêt)
est plus robuste et directement agrégeable en DAX.

## Fichiers

- **`Production.pq`** — requête complète et indépendante : appel API,
  aplatissement JSON, retrait de `issue_type_durations`, puis anti-doublon.
  Une ligne par shift dédupliqué, avec quantités (nette/conforme/rebut) et
  temps productif.
- **`Arrets.pq`** — requête complète et indépendante (même appel API), qui
  applique le **même anti-doublon** que `Production.pq` (mêmes 5 clés) avant
  de ne garder que les colonnes d'identité jusqu'à `Equipe` (shift_key) +
  `issue_type_durations`. Ce record est ensuite converti en table longue via
  `Record.ToTable` : une ligne par `(id, Type Arret)` avec `Duree Arret (s)`.
  Les sous-catégories `_details` sont exclues (pas développées ici) — et donc
  pas d'`Occurrences`/`Loss Level0 Id/Name` non plus : au 1er niveau,
  Teeptrak ne renvoie qu'une durée totale par catégorie (un nombre), le détail
  par sous-cause n'existe que dans `_details`.

Les deux fichiers dupliquent volontairement l'appel API et la logique
anti-doublon plutôt que de passer par une requête de staging partagée : vous
pouvez les coller tels quels dans deux requêtes Power BI séparées, sans étape
intermédiaire à créer.

## Logique anti-doublon (identique dans les 2 fichiers)

Clé = `Date de Production | Equipe | Machine | Atelier | Produit` (les 5
clés). Pour chaque valeur de clé en doublon, on ne garde que la ligne dont
l'`id` est le plus grand :

```
Table.Group(table, {"Cle_5"}, {
    {"Ligne", each Table.FirstN(Table.Sort(_, {{"id", Order.Descending}}), 1)}
})
```

Côté `Arrets.pq`, cet anti-doublon est appliqué **avant** l'éclatement de
`issue_type_durations` en lignes, pour dédupliquer au niveau du poste et non
au niveau de chaque ligne d'arrêt.

## Erreurs API neutralisées en 0

Sur certains postes (ex. pseudo-shifts de fermeture site), Teeptrak peut
renvoyer une valeur non calculable (division par zéro, etc.) sur
`net_count`/`good_count`/`bad_count`/`productive_duration` côté Production,
ou sur la durée d'une catégorie côté Arrêts. `Table.ReplaceErrorValues` est
appliqué en toute fin de chaîne pour remplacer ces erreurs par `0`, sinon
elles cassent les mesures DAX en aval.

## Mise en place dans Power BI

1. Créer un paramètre texte **`Bearer_Token`** (Accueil > Gérer les
   paramètres > Nouveau paramètre) et y coller le token — ne jamais le coder
   en dur dans le M si le fichier est versionné/partagé.
2. Créer une requête vide `Production`, coller le contenu de `Production.pq`
   dans l'éditeur avancé.
3. Créer une requête vide `Arrets`, coller le contenu de `Arrets.pq`.
4. Dans le modèle, créer une relation **`Production[id]` (1) → `Arrets[id]`
   (plusieurs)**. Les mesures TRS/OEE (temps d'arrêt par type, disponibilité,
   etc.) s'appuient sur `SUM(Arrets[Duree Arret (s)])` filtré par
   `[Type Arret]`, avec la table `Production` comme table de dimension pour
   Date/Équipe/Machine/Atelier/Produit.
