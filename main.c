// Sakarin Villapaitapeli - minimal C + raylib port (320x200, 8 colours, 8 kHz sound)
#include <math.h>
#include "raylib.h"
#include "rlgl.h"

enum { I_TITLE, I_ALOITA, I_QUEST, I_EN, I_JOO, I_HMM, I_SURPR, I_SWEATER,
       I_SHIRT, I_HIHI, I_LOST, I_WON, I_RETRY, I_COUNT };
static const char *IMG[] = { "sakarin_villapaitapeli", "aloita", "pue_sakarille_villapaita",
    "en", "joo", "sakari_hmm", "sakari_yllattynyt", "villapaita", "sakari_villapaidalla",
    "hihihi_kutittaa", "havisit_pelin", "voitit_pelin", "uudelleen" };

enum { W_INTRO, W_QUEST, W_HMM, W_HIHI, W_LOST, W_WON, W_COUNT };
static const char *SND[] = { "sakarin_villapaitapeli", "pue_sakarille_villapaita", "hmm",
    "hihihi_kutittaa", "havisit_pelin", "voitit_pelin" };

enum { INTRO, QUESTION, SEL_NO, SEL_YES, TICKLING, LOST, WON };

typedef struct { int img, x, y, next; } Btn;  // key = button index + 1
typedef struct {
    int img, x, y, snd;  // main picture, sound (-1 = silence)
    Btn btn[2];          // img < 0 = unused
    int next;            // auto-advance target (-1 = none)
    float wait;          // > 0: advance after seconds, 0: when sound ends
} Stage;

#define NB {-1}, {-1}
static const Stage S[] = {
    [INTRO]    = { I_TITLE, -5, 7,  W_INTRO, {{I_ALOITA, 151, 87, QUESTION}, {-1}}, -1, 0 },
    [QUESTION] = { I_QUEST, 27, 8,  W_QUEST, {{I_EN, 195, 71, SEL_NO}, {I_JOO, 196, 136, SEL_YES}}, -1, 0 },
    [SEL_NO]   = { I_HMM,   47, 4,  W_HMM,   {NB}, LOST, 0 },
    [SEL_YES]  = { I_SURPR, 55, 5,  -1,      {NB}, TICKLING, 1.5f },
    [TICKLING] = { I_SHIRT, 55, 13, W_HIHI,  {NB}, WON, 0 },
    [LOST]     = { I_LOST,  -5, 13, W_LOST,  {{I_RETRY, 134, 154, INTRO}, {-1}}, -1, 0 },
    [WON]      = { I_WON,  -15, 8,  W_WON,   {{I_RETRY, 131, 154, INTRO}, {-1}}, -1, 0 },
};
static const Vector2 SHAKE[3] = { {0, 0}, {3, -3}, {-1, 2} };

static Texture2D tex[I_COUNT];
static Sound snd[W_COUNT];
static int cur;
static float t;

static void Go(int s) {
    for (int i = 0; i < W_COUNT; i++) StopSound(snd[i]);
    if (S[s].snd >= 0) PlaySound(snd[S[s].snd]);
    cur = s;
    t = 0;
}

int main(void) {
    InitWindow(960, 720, "Sakarin Villapaitapeli");  // 320x200 shown at 4:3
    InitAudioDevice();
    SetTargetFPS(60);
    SetMouseScale(1 / 3.0f, 1 / 3.6f);
    ChangeDirectory(GetApplicationDirectory());
    for (int i = 0; i < I_COUNT; i++) tex[i] = LoadTexture(TextFormat("assets/images/%s.png", IMG[i]));
    for (int i = 0; i < W_COUNT; i++) snd[i] = LoadSound(TextFormat("assets/sounds/%s.wav", SND[i]));
    Go(INTRO);

    while (!WindowShouldClose()) {
        t += GetFrameTime();
        const Stage *st = &S[cur];
        int next = -1;

        BeginDrawing();
        ClearBackground(WHITE);
        rlPushMatrix();
        rlScalef(3, 3.6f, 1);

        Vector2 o = cur == TICKLING ? SHAKE[(int)(fmodf(t, 0.35f) / 0.35f * 3)] : (Vector2){0};
        DrawTexture(tex[st->img], st->x + o.x, st->y + o.y, WHITE);
        if (cur == SEL_YES) {
            int step = t >= 1.5f ? 16 : (int)(t / 1.5f * 16);
            DrawTexture(tex[I_SWEATER], -185 + (int)(229.8f * step / 16), 116, WHITE);
        }
        if (cur == TICKLING) DrawTexture(tex[I_HIHI], 4, 31, WHITE);

        for (int i = 0; i < 2; i++) {
            const Btn *b = &st->btn[i];
            if (b->img < 0) continue;
            DrawTexture(tex[b->img], b->x, b->y, WHITE);
            Rectangle r = { b->x, b->y, tex[b->img].width, tex[b->img].height };
            if ((IsMouseButtonPressed(MOUSE_BUTTON_LEFT) && CheckCollisionPointRec(GetMousePosition(), r))
                || IsKeyPressed(KEY_ONE + i)) next = b->next;
        }
        if (st->next >= 0 && (st->wait > 0 ? t >= st->wait : !IsSoundPlaying(snd[st->snd])))
            next = st->next;

        rlPopMatrix();
        EndDrawing();
        if (next >= 0) Go(next);
    }
    CloseAudioDevice();
    CloseWindow();
    return 0;
}
