; Packed assets, generated into build/ by tools/c64_assets.py
.macro BIN name, file
        .export name
name:   .incbin file
.endmacro
.macro SND name, file
        .export name, .ident(.concat(.string(name), "_end"))
name:   .incbin file
.ident(.concat(.string(name), "_end")):
.endmacro

.segment "RODATA"
        BIN _scr_intro_bm,     "build/scr_intro.bm.zx02"
        BIN _scr_intro_col,    "build/scr_intro.col.zx02"
        BIN _scr_question_bm,  "build/scr_question.bm.zx02"
        BIN _scr_question_col, "build/scr_question.col.zx02"
        BIN _scr_selno_bm,     "build/scr_selno.bm.zx02"
        BIN _scr_selno_col,    "build/scr_selno.col.zx02"
        BIN _scr_selyes_bm,    "build/scr_selyes.bm.zx02"
        BIN _scr_selyes_col,   "build/scr_selyes.col.zx02"
        BIN _scr_tickling_bm,  "build/scr_tickling.bm.zx02"
        BIN _scr_tickling_col, "build/scr_tickling.col.zx02"
        BIN _scr_lost_bm,      "build/scr_lost.bm.zx02"
        BIN _scr_lost_col,     "build/scr_lost.col.zx02"
        BIN _scr_won_bm,       "build/scr_won.bm.zx02"
        BIN _scr_won_col,      "build/scr_won.col.zx02"
        BIN _sweater_zx02,     "build/sweater.zx02"
        SND _snd_intro,        "build/snd_sakarin_villapaitapeli.bin"
        SND _snd_question,     "build/snd_pue_sakarille_villapaita.bin"
        SND _snd_hmm,          "build/snd_hmm.bin"
        SND _snd_hihi,         "build/snd_hihihi_kutittaa.bin"
        SND _snd_lost,         "build/snd_havisit_pelin.bin"
        SND _snd_won,          "build/snd_voitit_pelin.bin"
