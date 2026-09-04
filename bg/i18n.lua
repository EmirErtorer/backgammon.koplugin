-- Tiny self-contained localisation. Call the module like a function:
--   local T = require("bg/i18n"); T("roll"); T("game_n", 3)
-- Language comes from the plugin's own "language" setting (auto | en | tr);
-- "auto" follows KOReader's UI language. Falls back to English for any missing
-- key, so partial translations never break the UI.

local S = {
    en = {
        -- common
        close = "Close", done = "Done", new_game = "New game", menu = "Menu",
        -- setup
        app_title = "Backgammon", choose_game = "Choose your game",
        board_colours = "Board & colours", statistics = "Statistics",
        opponent = "OPPONENT",
        two_players = "Two players", two_players_sub = "Share the device, take turns",
        play_computer = "Play the computer", play_computer_sub = "One player against the machine",
        difficulty = "DIFFICULTY", start_game = "Start game",
        -- levels
        lvl1_name = "Beginner", lvl1_desc = "Loose play, leaves easy shots",
        lvl2_name = "Casual", lvl2_desc = "Plays safe, punishes blots",
        lvl3_name = "Skilled", lvl3_desc = "Looks a roll ahead, plays the odds",
        lvl4_name = "Expert", lvl4_desc = "GNU neural net, world-class judgement",
        lvl5_name = "Master", lvl5_desc = "GNU neural net, looks a roll ahead",
        -- board & colours settings
        settings_title = "Board & colours",
        player1_note = "Player 1 sees the device logo the right way up",
        player1_plays = "PLAYER 1 PLAYS", white = "White", black = "Black",
        bear_off_on = "BEAR OFF ON THE", left = "Left", right = "Right",
        flip_each_turn = "FLIP BOARD EACH TURN (2 PLAYERS)", on = "On", off = "Off",
        language = "LANGUAGE", lang_auto = "Auto", lang_en = "English", lang_tr = "Türkçe",
        -- board / play
        your_turn = "Your turn", computers_turn = "Computer's turn",
        computer_thinking = "Computer is thinking\u{2026}",
        to_play = "%s to play", game_n = "Game %d",
        roll = "Roll", next_game = "Next game", review = "Review",
        you = "You", computer = "Computer",
        cant_come_in = "%s can't come in", cant_move = "%s can't move",
        no_moves_either = "No legal moves for either player",
        no_legal_move = "No legal move",
        roll_to_start = "Roll to see who starts",
        roll_one_each = "Roll one die each to see who starts",
        both_rolled = "Both rolled %d. Roll again",
        opening_result = "%s %d, %s %d. %s starts, roll again",
        win_1 = "%s wins 1 point", win_n = "%s wins %d points",
        -- stats
        stats_title = "Statistics",
        games_played = "Games played", vs_computer = "VS THE COMPUTER",
        win_streak = "Win streak", best_streak = "best %d",
        record_fmt = "%d / %d  (%d%%)", no_games_yet = "No games played yet",
        -- review
        review_title = "Game review",
        review_none = "No clear mistakes \u{2014} well played!",
        review_summary = "%s: %d blunders, %d slips",
        review_line = "%d. %s  %s  (-%.2f)",
        review_best = "best: %s",
        review_working = "Analysing\u{2026}",
    },
    tr = {
        close = "Kapat", done = "Tamam", new_game = "Yeni oyun", menu = "Menü",
        app_title = "Tavla", choose_game = "Oyununu seç",
        board_colours = "Tahta ve renkler", statistics = "İstatistikler",
        opponent = "RAKİP",
        two_players = "İki oyuncu", two_players_sub = "Cihazı paylaşın, sırayla oynayın",
        play_computer = "Bilgisayara karşı", play_computer_sub = "Makineye karşı tek oyuncu",
        difficulty = "ZORLUK", start_game = "Oyunu başlat",
        lvl1_name = "Acemi", lvl1_desc = "Gevşek oynar, kolay açık bırakır",
        lvl2_name = "Sıradan", lvl2_desc = "Güvenli oynar, açıkları cezalandırır",
        lvl3_name = "Yetenekli", lvl3_desc = "Bir zar ileri bakar, olasılık oynar",
        lvl4_name = "Uzman", lvl4_desc = "GNU sinir ağı, dünya çapında sezgi",
        lvl5_name = "Usta", lvl5_desc = "GNU sinir ağı, bir zar ileri bakar",
        settings_title = "Tahta ve renkler",
        player1_note = "1. oyuncu cihaz logosunu düz görür",
        player1_plays = "1. OYUNCU", white = "Beyaz", black = "Siyah",
        bear_off_on = "TOPLAMA YÖNÜ", left = "Sol", right = "Sağ",
        flip_each_turn = "HER ELDE TAHTAYI ÇEVİR (2 OYUNCU)", on = "Açık", off = "Kapalı",
        language = "DİL", lang_auto = "Otomatik", lang_en = "İngilizce", lang_tr = "Türkçe",
        your_turn = "Senin sıran", computers_turn = "Bilgisayarın sırası",
        computer_thinking = "Bilgisayar düşünüyor\u{2026}",
        to_play = "Sıra: %s", game_n = "%d. oyun",
        roll = "Zar at", next_game = "Sonraki oyun", review = "İnceleme",
        you = "Sen", computer = "Bilgisayar",
        cant_come_in = "%s giremiyor", cant_move = "%s oynayamıyor",
        no_moves_either = "İki oyuncunun da hamlesi yok",
        no_legal_move = "Oynanacak hamle yok",
        roll_to_start = "Kimin başlayacağı için zar at",
        roll_one_each = "Kimin başlayacağı için birer zar atın",
        both_rolled = "İkiniz de %d attınız. Tekrar atın",
        opening_result = "%s %d, %s %d. %s başlıyor, tekrar at",
        win_1 = "%s 1 sayı kazandı", win_n = "%s %d sayı kazandı",
        stats_title = "İstatistikler",
        games_played = "Oynanan oyun", vs_computer = "BİLGİSAYARA KARŞI",
        win_streak = "Galibiyet serisi", best_streak = "en iyi %d",
        record_fmt = "%d / %d  (%%%d)", no_games_yet = "Henüz oyun oynanmadı",
        stats_title2 = "İstatistikler",
        review_title = "Oyun incelemesi",
        review_none = "Belirgin bir hata yok \u{2014} iyi oynadın!",
        review_summary = "%s: %d büyük hata, %d küçük hata",
        review_line = "%d. %s  %s  (-%.2f)",
        review_best = "en iyi: %s",
        review_working = "İnceleniyor\u{2026}",
    },
}

local I = {}
local cur

local function detect()
    -- explicit plugin setting wins; "auto"/nil follows KOReader
    local ok, Settings = pcall(require, "bg/settings")
    local pref = ok and Settings.get("language") or "auto"
    if pref == "tr" then return "tr" end
    if pref == "en" then return "en" end
    local ok2, G = pcall(function() return G_reader_settings end)
    if ok2 and G and G.readSetting then
        local l = G:readSetting("language")
        if type(l) == "string" and l:sub(1, 2):lower() == "tr" then return "tr" end
    end
    return "en"
end

function I.lang() if not cur then cur = detect() end return cur end
function I.refresh() cur = detect() end   -- call after the language setting changes

setmetatable(I, { __call = function(_, key, ...)
    local L = I.lang()
    local s = (S[L] and S[L][key]) or S.en[key] or key
    if select("#", ...) > 0 then return string.format(s, ...) end
    return s
end })

return I
