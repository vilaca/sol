"""Writes App/Localizable.xcstrings: English base plus pt-PT, pt-BR, es, fr and de.

This file is the source of the translations: add or change strings here, then run
    python3 scripts/translations.py
and commit both files. Don't edit the catalog in Xcode; the next run would overwrite it.

Each row: key -> {lang: value}. The key is the English text as the code writes it, with interpolated Ints as
%lld and Strings as %@; translations use positional %1$@, %2$@ when there are several. A tuple value is a
plural (one, other). en entries only where they differ from the key (plurals). Proper game names (Klondike,
FreeCell, ...) are not translated and need no row.
"""
import json
import os
import sys

LANGS = ["pt-PT", "pt-BR", "es", "fr", "de"]
NB = " "  # French narrow no-break space before ? ! :

def same(v):
    return {l: v for l in LANGS}

def pt(v_pt, es, fr, de, br=None):
    return {"pt-PT": v_pt, "pt-BR": br if br is not None else v_pt, "es": es, "fr": fr, "de": de}

T = {
    # Card names
    "%@ of %@": pt("%1$@ de %2$@", "%1$@ de %2$@", "%1$@ de %2$@", "%2$@ %1$@"),
    "Ace": pt("Ás", "As", "As", "Ass"),
    "Jack": pt("Valete", "Jota", "Valet", "Bube"),
    "Queen": pt("Dama", "Reina", "Dame", "Dame"),
    "King": pt("Rei", "Rey", "Roi", "König"),
    "spades": pt("espadas", "picas", "pique", "Pik"),
    "hearts": pt("copas", "corazones", "cœur", "Herz"),
    "diamonds": pt("ouros", "diamantes", "carreau", "Karo"),
    "clubs": pt("paus", "tréboles", "trèfle", "Kreuz"),
    "Face-down card": pt("Carta virada para baixo", "Carta boca abajo", "Carte face cachée", "Verdeckte Karte"),

    # VoiceOver labels and announcements
    "Column %lld": pt("Coluna %lld", "Columna %lld", "Colonne %lld", "Spalte %lld"),
    "Free cell %lld": pt("Célula livre %lld", "Celda libre %lld", "Cellule libre %lld", "Freie Zelle %lld"),
    "Foundation": pt("Base", "Fundación", "Fondation", "Zielstapel"),
    "Waste": pt("Descarte", "Descarte", "Défausse", "Abwurfstapel"),
    "Stock": pt("Baralho", "Mazo", "Pioche", "Stapel", br="Monte"),
    "%@, empty": pt("%@, vazia", "%@, vacía", "%@, vide", "%@, leer"),
    ", ": same(", "),
    "%lld hidden cards": {
        "en": ("%lld hidden card", "%lld hidden cards"),
        "pt-PT": ("%lld carta oculta", "%lld cartas ocultas"),
        "pt-BR": ("%lld carta oculta", "%lld cartas ocultas"),
        "es": ("%lld carta oculta", "%lld cartas ocultas"),
        "fr": ("%lld carte cachée", "%lld cartes cachées"),
        "de": ("%lld verdeckte Karte", "%lld verdeckte Karten"),
    },
    "under %lld cards": {
        "en": ("under %lld card", "under %lld cards"),
        "pt-PT": ("debaixo de %lld carta", "debaixo de %lld cartas"),
        "pt-BR": ("debaixo de %lld carta", "debaixo de %lld cartas"),
        "es": ("debajo de %lld carta", "debajo de %lld cartas"),
        "fr": ("sous %lld carte", "sous %lld cartes"),
        "de": ("unter %lld Karte", "unter %lld Karten"),
    },
    "Draw card, %lld left": {
        "en": ("Draw card, %lld left", "Draw card, %lld left"),
        "pt-PT": ("Virar carta, resta %lld", "Virar carta, restam %lld"),
        "pt-BR": ("Virar carta, resta %lld", "Virar carta, restam %lld"),
        "es": ("Robar carta, queda %lld", "Robar carta, quedan %lld"),
        "fr": ("Piocher une carte, %lld restante", "Piocher une carte, %lld restantes"),
        "de": ("Karte ziehen, noch %lld", "Karte ziehen, noch %lld"),
    },
    "Turn the waste over": pt("Virar o descarte", "Dar la vuelta al descarte", "Retourner la défausse", "Abwurfstapel umdrehen"),
    "Stock empty": pt("Baralho vazio", "Mazo vacío", "Pioche vide", "Stapel leer", br="Monte vazio"),
    "Scorpion": pt("Escorpião", "Escorpión", "Scorpion", "Skorpion"),
    "Deal the reserve": pt("Distribuir a reserva", "Repartir la reserva", "Distribuer la réserve", "Reserve austeilen"),
    "Reserve empty": pt("Reserva vazia", "Reserva vacía", "Réserve vide", "Reserve leer"),
    "Reserve dealt": pt("Reserva distribuída", "Reserva repartida", "Réserve distribuée", "Reserve ausgeteilt"),
    "Golf": pt("Golfe", "Golf", "Golf", "Golf"),
    "Wrap King and Ace": pt("Rei e Ás em ciclo", "Rey y As en círculo", "Roi et As consécutifs", "König und Ass verbinden"),
    "Move to waste": pt("Mover para o descarte", "Mover al descarte", "Déplacer vers la défausse", "Auf Abwurfstapel legen"),
    "waste": pt("a pilha de descarte", "la pila de descarte", "la défausse", "den Abwurfstapel"),
    "Peak %lld, row %lld": pt("Pico %1$lld, fila %2$lld", "Pico %1$lld, fila %2$lld", "Pic %1$lld, rangée %2$lld", "Gipfel %1$lld, Reihe %2$lld", br="Pico %1$lld, linha %2$lld"),
    "Pyramid": pt("Pirâmide", "Pirámide", "Pyramide", "Pyramide"),
    "Recycle the waste": pt("Reciclar o descarte", "Reciclar el descarte", "Recycler la défausse", "Abwurfstapel wiederverwenden", br="Reciclar o descarte"),
    "Never": pt("Nunca", "Nunca", "Jamais", "Nie"),
    "Once": pt("Uma vez", "Una vez", "Une fois", "Einmal"),
    "Twice": pt("Duas vezes", "Dos veces", "Deux fois", "Zweimal"),
    "Always": pt("Sempre", "Siempre", "Toujours", "Immer"),
    "Row %lld, card %lld": pt("Fila %1$lld, carta %2$lld", "Fila %1$lld, carta %2$lld", "Rangée %1$lld, carte %2$lld", "Reihe %1$lld, Karte %2$lld", br="Linha %1$lld, carta %2$lld"),
    "Pair with %@": pt("Juntar com %@", "Emparejar con %@", "Associer à %@", "Mit %@ paaren", br="Combinar com %@"),
    "%@ paired with %@": pt("%1$@ juntada com %2$@", "%1$@ emparejada con %2$@", "%1$@ associée à %2$@", "%1$@ mit %2$@ gepaart", br="%1$@ combinada com %2$@"),
    "Waste, %@": pt("Descarte, %@", "Descarte, %@", "Défausse, %@", "Abwurfstapel, %@"),
    "Foundation, %@": pt("Base, %@", "Fundación, %@", "Fondation, %@", "Zielstapel, %@"),
    "Empty foundation": pt("Base vazia", "Fundación vacía", "Fondation vide", "Leerer Zielstapel"),
    "Move to foundation": pt("Mover para a base", "Mover a la fundación", "Déplacer vers la fondation", "Auf Zielstapel legen"),
    "Move to %@": pt("Mover para %@", "Mover a %@", "Déplacer vers %@", "Auf %@ legen"),
    "%@ moved to %@": pt("%1$@ para %2$@", "%1$@ a %2$@", "%1$@ vers %2$@", "%1$@ auf %2$@"),
    "foundation": pt("a base", "la fundación", "la fondation", "den Zielstapel"),
    "revealed %@": pt("nova carta: %@", "nueva carta: %@", f"nouvelle carte{NB}: %@", "aufgedeckt: %@"),
    "Drew %@": pt("Carta virada: %@", "Carta robada: %@", f"Carte piochée{NB}: %@", "Gezogen: %@"),
    "Waste turned over": pt("Descarte virado", "Descarte volteado", "Défausse retournée", "Abwurfstapel umgedreht"),
    "Not allowed": pt("Não permitido", "No permitido", "Impossible", "Nicht erlaubt"),
    "Time %@": pt("Tempo %@", "Tiempo %@", "Temps %@", "Zeit %@"),

    # Toolbar and dialogs
    "New": pt("Novo", "Nueva", "Nouvelle", "Neu"),
    "Undo": pt("Anular", "Deshacer", "Annuler", "Widerrufen", br="Desfazer"),
    "Finish": pt("Terminar", "Terminar", "Terminer", "Abschließen"),
    "More": pt("Mais", "Más", "Plus", "Mehr"),
    "Moves: %lld": pt("Jogadas: %lld", "Movimientos: %lld", f"Coups{NB}: %lld", "Züge: %lld", br="Movimentos: %lld"),
    "Statistics…": pt("Estatísticas…", "Estadísticas…", "Statistiques…", "Statistik…"),
    "Settings…": pt("Definições…", "Ajustes…", "Réglages…", "Einstellungen…", br="Ajustes…"),
    "Abandon this game?": pt("Desistir deste jogo?", "¿Abandonar esta partida?", f"Abandonner cette partie{NB}?", "Dieses Spiel aufgeben?"),
    "It counts as a loss.": pt("Conta como derrota.", "Cuenta como derrota.", "Elle compte comme une défaite.", "Es zählt als Niederlage."),
    "Abandon and Deal": pt("Desistir e dar cartas", "Abandonar y repartir", "Abandonner et redistribuer", "Aufgeben und neu geben", br="Desistir e distribuir"),

    # Win banner
    "You won!": pt("Ganhou!", "¡Has ganado!", f"Gagné{NB}!", "Gewonnen!", br="Você venceu!"),
    "%lld moves": {
        "en": ("%lld move", "%lld moves"),
        "pt-PT": ("%lld jogada", "%lld jogadas"),
        "pt-BR": ("%lld movimento", "%lld movimentos"),
        "es": ("%lld movimiento", "%lld movimientos"),
        "fr": ("%lld coup", "%lld coups"),
        "de": ("%lld Zug", "%lld Züge"),
    },
    "New best time!": pt("Novo melhor tempo!", "¡Nuevo mejor tiempo!", f"Nouveau meilleur temps{NB}!", "Neue Bestzeit!"),
    "Fewest moves yet!": pt("Recorde de jogadas!", "¡Récord de movimientos!", f"Record de coups{NB}!", "Neuer Zug-Rekord!", br="Recorde de movimentos!"),
    "Play again": pt("Jogar outra vez", "Jugar otra vez", "Rejouer", "Nochmal spielen", br="Jogar de novo"),

    # Statistics
    "Statistics": pt("Estatísticas", "Estadísticas", "Statistiques", "Statistik"),
    "Deal": pt("Modo de jogo", "Modo de juego", "Mode de jeu", "Spielmodus"),
    "Draw 1": pt("Virar 1", "Robar 1", "Piocher 1", "1 Karte ziehen"),
    "Draw 3": pt("Virar 3", "Robar 3", "Piocher 3", "3 Karten ziehen"),
    "Games": pt("Jogos", "Partidas", "Parties", "Spiele"),
    "Played": pt("Jogados", "Jugadas", "Jouées", "Gespielt"),
    "Won": pt("Ganhos", "Ganadas", "Gagnées", "Gewonnen"),
    "Win rate": pt("Percentagem de vitórias", "Porcentaje de victorias", "Taux de victoire", "Gewinnquote", br="Porcentagem de vitórias"),
    "Streaks": pt("Sequências", "Rachas", "Séries", "Serien"),
    "Current streak": pt("Sequência atual", "Racha actual", "Série en cours", "Aktuelle Serie"),
    "Best streak": pt("Melhor sequência", "Mejor racha", "Meilleure série", "Längste Serie"),
    "Best game": pt("Melhor jogo", "Mejor partida", "Meilleure partie", "Bestes Spiel"),
    "Best time": pt("Melhor tempo", "Mejor tiempo", "Meilleur temps", "Bestzeit"),
    "Fewest moves": pt("Menos jogadas", "Menos movimientos", "Moins de coups", "Wenigste Züge", br="Menos movimentos"),
    "Reset Statistics": pt("Repor estatísticas", "Restablecer estadísticas", "Réinitialiser les statistiques", "Statistik zurücksetzen", br="Redefinir estatísticas"),
    "Game": pt("Jogo", "Juego", "Jeu", "Spiel"),
    "Reset the statistics of %@?": pt("Repor as estatísticas de %@?", "¿Restablecer las estadísticas de %@?", f"Réinitialiser les statistiques de %@{NB}?", "Statistik für %@ zurücksetzen?", br="Redefinir as estatísticas de %@?"),
    "It can't be undone.": pt("Não pode ser anulado.", "No se puede deshacer.", "Cette action est irréversible.", "Das lässt sich nicht widerrufen.", br="Não é possível desfazer."),
    "Reset": pt("Repor", "Restablecer", "Réinitialiser", "Zurücksetzen", br="Redefinir"),
    "Done": pt("OK", "OK", "OK", "Fertig"),

    # Hint and dead ends
    "Hint": pt("Dica", "Pista", "Indice", "Tipp"),
    "Hint: move %@ to %@": pt("Dica: mover %1$@ para %2$@", "Pista: mover %1$@ a %2$@", f"Indice{NB}: déplacer %1$@ vers %2$@", "Tipp: %1$@ auf %2$@ legen"),
    "Hint: deal the reserve": pt("Dica: distribuir a reserva", "Pista: repartir la reserva", f"Indice{NB}: distribuer la réserve", "Tipp: Reserve austeilen"),
    "Spider": pt("Aranha", "Araña", "Araignée", "Spinne"),
    "Forty Thieves": pt("Quarenta Ladrões", "Los cuarenta ladrones", "Les quarante voleurs", "Vierzig Räuber", br="Quarenta Ladrões"),
    "Suits": pt("Naipes", "Palos", "Couleurs", "Farben", br="Naipes"),
    "1 suit": pt("1 naipe", "1 palo", "1 couleur", "1 Farbe"),
    "2 suits": pt("2 naipes", "2 palos", "2 couleurs", "2 Farben"),
    "4 suits": pt("4 naipes", "4 palos", "4 couleurs", "4 Farben"),
    "Deal a row": pt("Distribuir uma fila", "Repartir una fila", "Distribuer une rangée", "Reihe austeilen", br="Distribuir uma linha"),
    "Row dealt": pt("Fila distribuída", "Fila repartida", "Rangée distribuée", "Reihe ausgeteilt", br="Linha distribuída"),
    "Hint: deal a row": pt("Dica: distribuir uma fila", "Pista: repartir una fila", f"Indice{NB}: distribuer une rangée", "Tipp: Reihe austeilen", br="Dica: distribuir uma linha"),
    "Hint: draw a card": pt("Dica: virar uma carta", "Pista: robar una carta", f"Indice{NB}: piocher une carte", "Tipp: eine Karte ziehen"),
    "Hint: turn the waste over": pt("Dica: virar o descarte", "Pista: dar la vuelta al descarte", f"Indice{NB}: retourner la défausse", "Tipp: Abwurfstapel umdrehen"),
    "No moves left": pt("Sem jogadas possíveis", "No quedan movimientos", "Plus aucun coup possible", "Keine Züge mehr möglich", br="Sem movimentos possíveis"),
    "Undo, or deal a new game. A new game counts as a loss.": pt(
        "Anule jogadas ou comece um novo jogo. Um novo jogo conta como derrota.",
        "Deshaz movimientos o reparte una partida nueva. Una partida nueva cuenta como derrota.",
        "Annulez des coups ou lancez une nouvelle partie. Une nouvelle partie compte comme une défaite.",
        "Mach Züge rückgängig oder starte ein neues Spiel. Ein neues Spiel zählt als Niederlage.",
        br="Desfaça movimentos ou comece um novo jogo. Um novo jogo conta como derrota.",
    ),
    "New Game": pt("Novo jogo", "Nueva partida", "Nouvelle partie", "Neues Spiel"),
    "Keep Playing": pt("Continuar", "Seguir jugando", "Continuer", "Weiterspielen"),

    # About and welcome
    "About Sol…": pt("Acerca do Sol…", "Acerca de Sol…", "À propos de Sol…", "Über Sol…", br="Sobre o Sol…"),
    "About": pt("Acerca de", "Acerca de", "À propos", "Über", br="Sobre"),
    "Welcome to Sol": pt("Boas-vindas ao Sol", "Te damos la bienvenida a Sol", "Bienvenue dans Sol", "Willkommen bei Sol"),
    "Play": pt("Jogar", "Jugar", "Jouer", "Spielen"),
    "Version %@": pt("Versão %@", "Versión %@", "Version %@", "Version %@"),
    "Solitaire card games, free for everyone.": pt("Jogos de paciência, grátis para todos.", "Juegos de solitario, gratis para todos.", "Des jeux de solitaire, gratuits pour tous.", "Solitaire-Kartenspiele, kostenlos für alle."),
    "Our promise": pt("A nossa promessa", "Nuestra promesa", "Notre promesse", "Unser Versprechen", br="Nossa promessa"),
    "100% free: no pay to play, no pay to win": pt(
        "100% grátis: sem pagar para jogar nem para ganhar",
        "100% gratis: sin pagar por jugar ni por ganar",
        f"100{NB}% gratuit{NB}: rien à payer pour jouer ni pour gagner",
        "100 % kostenlos: kein Pay-to-Play, kein Pay-to-Win",
    ),
    "No ads": pt("Sem publicidade", "Sin anuncios", "Aucune publicité", "Keine Werbung", br="Sem anúncios"),
    "No in-app purchases": pt("Sem compras na app", "Sin compras dentro de la app", "Aucun achat intégré", "Keine In-App-Käufe", br="Sem compras no app"),
    "No tracking, no analytics, no account": pt(
        "Sem rastreio, sem análise de utilização, sem conta",
        "Sin rastreo, sin analíticas, sin cuenta",
        "Aucun pistage, aucune analyse, aucun compte",
        "Kein Tracking, keine Analyse, kein Konto",
        br="Sem rastreamento, sem análise de uso, sem conta",
    ),
    "Works offline: nothing leaves your device": pt(
        "Funciona sem internet: nada sai do seu dispositivo",
        "Funciona sin conexión: nada sale de tu dispositivo",
        f"Fonctionne hors ligne{NB}: rien ne quitte votre appareil",
        "Funktioniert offline: Nichts verlässt dein Gerät",
        br="Funciona offline: nada sai do seu aparelho",
    ),
    "Source code on GitHub": pt("Código-fonte no GitHub", "Código fuente en GitHub", "Code source sur GitHub", "Quellcode auf GitHub"),
    "Privacy policy": pt("Política de privacidade", "Política de privacidad", "Politique de confidentialité", "Datenschutzerklärung"),
    "Sol is open source under the MIT license: anyone can read the code, check these promises and help improve it.": pt(
        "O Sol é código aberto, com licença MIT: qualquer pessoa pode ler o código, confirmar estas promessas e ajudar a melhorá-lo.",
        "Sol es de código abierto con licencia MIT: cualquiera puede leer el código, comprobar estas promesas y ayudar a mejorarlo.",
        f"Sol est open source sous licence MIT{NB}: chacun peut lire le code, vérifier ces promesses et aider à l’améliorer.",
        "Sol ist Open Source unter der MIT-Lizenz: Jeder kann den Code lesen, diese Versprechen prüfen und mithelfen, ihn zu verbessern.",
        br="O Sol é de código aberto, sob a licença MIT: qualquer pessoa pode ler o código, conferir estas promessas e ajudar a melhorá-lo.",
    ),

    # Settings
    "Settings": pt("Definições", "Ajustes", "Réglages", "Einstellungen", br="Ajustes"),
    "Haptics": pt("Resposta tátil", "Respuesta háptica", "Retour haptique", "Haptisches Feedback"),
    "Show timer": pt("Mostrar cronómetro", "Mostrar cronómetro", "Afficher le chrono", "Timer anzeigen", br="Mostrar cronômetro"),
    "Off": pt("Desativado", "Desactivado", "Désactivé", "Aus"),
    "On": pt("Ativado", "Activado", "Activé", "Ein"),
    "Empty columns": pt("Colunas vazias", "Columnas vacías", "Colonnes vides", "Leere Spalten"),
    "Kings only": pt("Só reis", "Solo reyes", "Rois seulement", "Nur Könige", br="Só reis"),
    "Any card": pt("Qualquer carta", "Cualquier carta", "N’importe quelle carte", "Jede Karte"),
    "%@: %@": pt("%1$@: %2$@", "%1$@: %2$@", f"%1$@{NB}: %2$@", "%1$@: %2$@"),
    "Applies from the next game.": pt("Aplica-se a partir do próximo jogo.", "Se aplica a partir de la próxima partida.", "S’applique à partir de la prochaine partie.", "Gilt ab dem nächsten Spiel.", br="Vale a partir do próximo jogo."),
}

COMMENTS = {
    "%@ of %@": "Card name: rank, then suit, e.g. Queen of hearts",
    ", ": "Separates the parts of a spoken card label",
    "foundation": "Spoken destination after a move: '<card> moved to foundation'",
    "Deal": "Picker label: draw 1 or draw 3",
    "%@: %@": "A rule option and its value, e.g. Recycle the waste: Twice",
    "waste": "Spoken destination after a move: '<card> moved to the waste pile' (Golf, TriPeaks)",
    "Pair with %@": "VoiceOver action on a Pyramid card: remove it together with another card that adds up to 13",
    "Row %lld, card %lld": "Pyramid position: row from the top, card from the left",
    "Peak %lld, row %lld": "TriPeaks position: which of the three peaks and which row from the top",
    "Free cell %lld": "A free cell, where one card can wait (FreeCell)",
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if isinstance(value, tuple):
        one, other = value
        return {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}
    return unit(value)


def main(path):
    strings = {}
    for key, values in sorted(T.items(), key=lambda kv: kv[0].lower()):
        entry = {}
        if key in COMMENTS:
            entry["comment"] = COMMENTS[key]
        entry["localizations"] = {lang: localization(v) for lang, v in values.items()}
        strings[key] = entry
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")
    print(f"{len(strings)} strings")


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "App", "Localizable.xcstrings"))
