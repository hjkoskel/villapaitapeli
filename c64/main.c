/* Sakarin villapaitapeli - Commodore 64 port (cc65).
 * Same 7-stage state machine as the raylib port; platform code is in sys.s.
 */
#include <string.h>

#define SCREEN ((unsigned char *)0xC000)
#define BITMAP ((unsigned char *)0xE000)
#define SWBUF  ((unsigned char *)0xC400)
#define BGBUF  ((unsigned char *)0xD000)
#define SW_ROW0 14
#define SW_ROWS 11

#define IN_B1 1   /* 1, E, N, joystick up   */
#define IN_B2 2   /* 2, J, Y, joystick down */
#define IN_GO 4   /* space, return, fire    */

extern volatile unsigned char frame, snd_done, vic_d011, vic_d016;
void __fastcall__ sys_init(unsigned char pal);
void __fastcall__ unzx02(const void *src, void *dst);
void __fastcall__ snd_play(const void *start, const void *end);
void snd_stop(void);
unsigned char read_input(void);
void __fastcall__ sweater_draw(signed char col);

#define ASSET(n) extern const unsigned char n##_bm[], n##_col[]
ASSET(scr_intro); ASSET(scr_question); ASSET(scr_selno); ASSET(scr_selyes);
ASSET(scr_tickling); ASSET(scr_lost); ASSET(scr_won);
#define SOUND(n) extern const unsigned char n[], n##_end[]
SOUND(snd_intro); SOUND(snd_question); SOUND(snd_hmm);
SOUND(snd_hihi); SOUND(snd_lost); SOUND(snd_won);
extern const unsigned char sweater_zx02[];

enum { INTRO, QUESTION, SEL_NO, SEL_YES, TICKLING, LOST, WON, NONE = 0xFF };

typedef struct {
    const unsigned char *bm, *col;      /* packed screen            */
    const unsigned char *snd, *snd_end; /* NULL = silence           */
    unsigned char b1, b2;               /* button targets           */
    unsigned char next;                 /* auto-advance target      */
} Stage;

static const Stage S[] = {
    { scr_intro_bm,    scr_intro_col,    snd_intro,    snd_intro_end,    QUESTION, NONE,    NONE },
    { scr_question_bm, scr_question_col, snd_question, snd_question_end, SEL_NO,   SEL_YES, NONE },
    { scr_selno_bm,    scr_selno_col,    snd_hmm,      snd_hmm_end,      NONE,     NONE,    LOST },
    { scr_selyes_bm,   scr_selyes_col,   0,            0,                NONE,     NONE,    TICKLING },
    { scr_tickling_bm, scr_tickling_col, snd_hihi,     snd_hihi_end,     NONE,     NONE,    WON },
    { scr_lost_bm,     scr_lost_col,     snd_lost,     snd_lost_end,     INTRO,    NONE,    NONE },
    { scr_won_bm,      scr_won_col,      snd_won,      snd_won_end,      INTRO,    NONE,    NONE },
};

/* tickling shake offsets {0,0} {3,-3} {-1,2} as fine-scroll values,
 * around a base of x=1, y=3 in 38-column / 24-row mode */
static const unsigned char SHAKE_X[3] = { 1, 4, 0 };
static const unsigned char SHAKE_Y[3] = { 3, 0, 5 };

static unsigned char cur, last, fps, shake_period, step;
static unsigned int t;              /* frames in the current stage */

#ifdef AUTOTEST
/* Plays through both endings without input: Aloita, Joo, Uudelleen,
 * Aloita, En, Uudelleen ... */
static const unsigned char autoseq[] = { IN_B1, IN_B2, IN_B1, IN_B1, IN_B1, IN_B1 };
static unsigned char autopos;
#endif

static void wait_frame(void)
{
    unsigned char f = frame;
    while (frame == f) ;
}

static signed char sweater_col(unsigned char k)
{
    /* CSS: x = -185 + 229.8 * k / 16, snapped to the nearest 8-px cell */
    int x = -185 + (int)((unsigned)2298 * k / 160);
    return (signed char)((x + 4 + 256) >> 3) - 32;
}

static void go(unsigned char s)
{
    const Stage *st = &S[s];
    vic_d011 = 0x2B;                    /* blank while unpacking */
    vic_d016 = 0x08;
    /* start the clip right away: it plays from NMI while the screen unpacks */
    if (st->snd) snd_play(st->snd, st->snd_end);
    else snd_stop();
    wait_frame();
    unzx02(st->bm, BITMAP);
    unzx02(st->col, SCREEN);
    if (s == SEL_YES) {
        unzx02(sweater_zx02, SWBUF);
        /* save the background band into the RAM under I/O */
        __asm__("sei");
        *(unsigned char *)1 = 0x34;
        memcpy(BGBUF, BITMAP + SW_ROW0 * 320, SW_ROWS * 320);
        memcpy(BGBUF + SW_ROWS * 320, SCREEN + SW_ROW0 * 40, SW_ROWS * 40);
        *(unsigned char *)1 = 0x35;
        __asm__("cli");
        step = 0;
        sweater_draw(sweater_col(0));
    }
    wait_frame();
    vic_d011 = 0x3B;
    cur = s;
    t = 0;
    last = frame;
}

void main(void)
{
    unsigned char in, prev = 0xFF, press, next, k;
    const Stage *st;

    unsigned char pal = *(unsigned char *)0x02A6;   /* KERNAL PAL flag */
    fps = pal ? 50 : 60;
    shake_period = pal ? 18 : 21;                   /* 0.35 s */
    sys_init(pal);
    go(INTRO);

    for (;;) {
        while (frame == last) ;
        t += (unsigned char)(frame - last);
        last = frame;

        in = read_input();
        press = in & ~prev;
        prev = in;
#ifdef AUTOTEST
        press = 0;
        if (S[cur].b1 != NONE && t >= 2 * fps && snd_done) {
            press = autoseq[autopos];
            autopos = (autopos + 1) % sizeof autoseq;
        }
#endif
        st = &S[cur];
        next = NONE;

        if (st->b2 != NONE) {               /* question: En / Joo */
            if (press & IN_B1) next = st->b1;
            if (press & IN_B2) next = st->b2;
        } else if (st->b1 != NONE && (press & (IN_B1 | IN_GO))) {
            next = st->b1;
        }

        if (cur == SEL_YES) {               /* 16 steps over 1.5 s */
            k = (unsigned char)(t * 32 / (3 * fps));
            if (k >= 16) {
                next = TICKLING;
            } else if (k != step) {
                step = k;
                sweater_draw(sweater_col(k));
            }
        } else if (cur == TICKLING) {
            k = (unsigned char)(t % shake_period) * 3 / shake_period;
            vic_d016 = 0x00 | SHAKE_X[k];
            vic_d011 = 0x30 | SHAKE_Y[k];
            if (snd_done) next = WON;
        } else if (st->next != NONE && snd_done) {
            next = st->next;
        }

        if (next != NONE) go(next);
    }
}
