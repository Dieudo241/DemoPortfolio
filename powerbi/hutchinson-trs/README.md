# Teeptrak → Power BI : TRS Hutchinson

Refonte de la requête Power Query d'origine (une seule table géante, tous les
sous-détails d'arrêt développés en colonnes) en un modèle en étoile à 2 tables,
avec un anti-doublon explicite sur les 5 clés métier.

## Pourquoi ce découpage

L'API Teeptrak peut renvoyer un enregistrement corrigé pour un même
(Date, Équipe, Machine, Atelier, Produit) sous un nouvel `id`. Sans clé de
dédoublonnage, ces mises à jour s'additionnent en double dans les totaux.

Développer `issue_type_durations` (et ses `_details` par sous-cause) colonne
par colonne rendait la table très large et cassante à chaque nouvelle cause
d'arrêt ajoutée côté Teeptrak. Le format long (une ligne par type d'arrêt)
est plus robuste et directement agrégeable en DAX.

## Fichiers

- **`Base.pq`** — requête de staging (désactiver "Activer le chargement").
  Appel API, aplatissement JSON, puis anti-doublon : clé =
  `Date de Production | Equipe | Machine | Atelier | Produit`, on garde la
  ligne avec l'`id` maximum par clé (`Table.Group` + `Table.Sort` desc +
  `Table.FirstN(_, 1)`).
- **`Production.pq`** — référence `Base`, retire `issue_type_durations` :
  quantités (nette/conforme/rebut) et temps productif, une ligne par shift
  dédupliqué.
- **`Arrets.pq`** — référence `Base`, ne garde que les colonnes d'identité
  jusqu'à `Equipe` (shift_key) + `issue_type_durations`, puis convertit ce
  record en table longue via `Record.ToTable` : une ligne par
  `(id, Type Arret)` avec `Duree Arret (s)`, `Occurrences`,
  `Loss Level0 Id/Name`. Les sous-catégories `_details` sont exclues (elles
  restent disponibles si besoin, mais ne sont pas développées ici).

## Mise en place dans Power BI

1. Créer un paramètre texte **`Bearer_Token`** (Accueil > Gérer les
   paramètres > Nouveau paramètre) et y coller le token — ne jamais le coder
   en dur dans le M si le fichier est versionné/partagé.
2. Créer la requête `Base` avec le contenu de `Base.pq`, puis clic droit >
   **Activer le chargement** pour la décocher (c'est une requête technique).
3. Créer `Production` et `Arrets` avec le contenu des fichiers correspondants
   (ils référencent `Base` par son nom de requête).
4. Dans le modèle, créer une relation **`Production[id]` (1) → `Arrets[id]`
   (plusieurs)**. Les mesures TRS/OEE (temps d'arrêt par type, disponibilité,
   etc.) s'appuient sur `SUM(Arrets[Duree Arret (s)])` filtré par
   `[Type Arret]`, avec la table `Production` comme table de dimension pour
   Date/Équipe/Machine/Atelier/Produit.
