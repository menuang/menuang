//+------------------------------------------------------------------+
//|                                                     MesinUang.mq5 |
//|  Full-margin slices + kunci (hedge) recovery                     |
//|  v2.30 - profil risiko: Konservatif (default) / Moderat /        |
//|          Agresif / Kustom. Panel interaktif, state tersimpan.    |
//|          + Standar keranjang (profit/rugi/kunci/flip) bisa diubah|
//|          + Garis Pra-Stop Out dan Stop Out                       |
//|          + Flip martingale (tutup sisi rugi, balik arah, lot xN) |
//|          + Entry sinyal (candle kiri/breakout/reversal), jarak   |
//|            flip ikut martingale (11% -> 22% -> 44%)             |
//+------------------------------------------------------------------+
#property copyright "Mesin Uang"
#property version   "2.30"
#property description "Mesin Uang: Full-margin slices + kunci (hedge) recovery. Default profil KONSERVATIF + standar keranjang."
#property strict

#include <Trade/Trade.mqh>

//--- enum
enum ENUM_NYESER_DIR { NYESER_BUY = 0, NYESER_SELL = 1 };
enum ENUM_PROFILE    { PROFILE_CONSERVATIVE = 0, PROFILE_MODERATE = 1, PROFILE_AGGRESSIVE = 2, PROFILE_CUSTOM = 3 };
enum ENUM_THEME      { THEME_DARK = 0, THEME_LIGHT = 1 };
enum ENUM_LANG       { LANG_ID = 0, LANG_EN = 1 };
enum ENUM_EA_STATE   { ST_IDLE, ST_BUILDING, ST_ACTIVE, ST_LOCKED, ST_COOLDOWN, ST_PAUSED };
enum ENUM_ENTRY_MODE { ENTRY_CANDLE = 0, ENTRY_BREAKOUT = 1, ENTRY_REVERSAL = 2, ENTRY_AUTO = 3, ENTRY_FIXED = 4 };

//--- input
input group "Profil risiko"
input ENUM_PROFILE    InpProfile               = PROFILE_CONSERVATIVE; // Konservatif / Moderat / Agresif / Kustom

input group "Standar keranjang (bisa diubah; saldo = saldo sebelum posisi dibuka)"
input bool            InpUseBasketStd          = true;   // true = pakai standar di bawah (menimpa profil), false = ikut profil
input double          InpBasketProfitPct       = 11.0;   // keranjang profit: % dari saldo sebelum posisi
input double          InpBasketLossPct         = 77.0;   // keranjang rugi: % dari saldo sebelum posisi
input double          InpKunciFlipPct          = 11.0;   // jarak flip pertama: rugi floating sisi utama >= N% saldo sebelum posisi
input bool            InpFlipMartingale        = true;   // flip martingale di ambang N%: sisi rugi ditutup semua, arah dibalik (butuh akun hedging)
input double          InpFlipLotMultiplier     = 2.0;    // lot sisi flip = lot sisi rugi x pengali (dibatasi margin bebas)
input double          InpFlipDistMultiplier    = 2.0;    // jarak flip berikutnya = jarak sebelumnya x pengali (11% -> 22% -> 44%)
input int             InpFlipMaxCount          = 3;      // jumlah flip maksimum per keranjang
input double          InpFlipMarginUsePct      = 90.0;   // batas pemakaian margin bebas untuk lot flip (%)
input double          InpStdKillPct            = 85.0;   // kill switch: equity turun N% dari saldo sebelum posisi, 0 = nonaktif
input double          InpStdEmergencySLPct     = 77.0;   // SL server darurat sisi utama (% saldo sebelum posisi), 0 = nonaktif
input bool            InpShowSOLine            = true;   // garis Stop Out
input bool            InpShowPreSOLine         = true;   // garis peringatan sebelum Stop Out
input double          InpPreSOBufferLevel      = 50.0;   // jarak garis pra-SO: level SO + N poin margin level

input group "Sinyal entry"
input ENUM_ENTRY_MODE InpEntryMode             = ENTRY_AUTO;   // CANDLE kiri / BREAKOUT / REVERSAL / AUTO (reversal > breakout > candle) / FIXED (ikut input arah)
input ENUM_TIMEFRAMES InpSignalTF              = PERIOD_CURRENT;
input int             InpBreakoutBars          = 10;     // breakout: close menembus high/low N bar sebelum kotak kiri
input double          InpPinWickRatio          = 0.60;   // reversal: ekor candle >= N x range (0.51 - 0.95)
input int             InpReentryAfterTargetSec = 0;      // jeda entry lagi setelah keranjang profit tercapai (detik), 0 = langsung

input group "Umum"
input long            InpMagic                 = 1970;
input bool            InpEnableTrading         = true;
input ENUM_NYESER_DIR InpDirection             = NYESER_BUY;
input bool            InpAutoSwitchDir         = true;   // arah siklus berikutnya mengikuti pemenang
input bool            InpKunciEnable           = true;   // butuh akun hedging
input int             InpSliceDelaySeconds     = 1;
input int             InpKunciSliceDelaySeconds= 1;
input int             InpSlippagePoints        = 30;
input int             InpMaxBasketSeconds      = 0;      // 0 = nonaktif
input bool            InpEntryAtSecond00       = false;

input group "Filter masuk (batas spread & ATR diatur oleh profil)"
input bool            InpUseSession            = false;
input int             InpSessionStartHour      = 7;      // jam server
input int             InpSessionEndHour        = 21;
input ENUM_TIMEFRAMES InpAtrTimeframe          = PERIOD_M15;

input group "Kustom (hanya dipakai jika Profil = KUSTOM)"
input double          InpCMarginUsagePercent   = 30.0;
input int             InpCSliceCount           = 3;
input double          InpCProfitBasketPercent  = 0.5;    // diabaikan jika Standar keranjang aktif
input double          InpCLossLimitPercent     = 0.5;    // diabaikan jika Standar keranjang aktif
input double          InpCKunciTriggerPercent  = 60.0;   // % dari batas rugi; diabaikan jika Standar keranjang aktif
input double          InpCKunciVolumeRatio     = 0.6;
input int             InpCKunciSliceCount      = 2;
input double          InpCKunciMarginReserve   = 30.0;
input double          InpCKunciRecoverPercent  = 0.15;
input double          InpCKunciReleasePercent  = 25.0;
input bool            InpCKunciFlipToWinner    = false;  // diabaikan jika Standar keranjang aktif
input double          InpCKunciFlipBufferPct   = 0.10;
input int             InpCMaxSpreadPoints      = 0;      // batas absolut (point), 0 = nonaktif
input double          InpCSpreadSpikeMult      = 2.0;    // tolak jika spread > N x rata-rata, 0 = nonaktif
input double          InpCMinMarginLevel       = 200.0;  // 0 = nonaktif
input double          InpCKillSwitchPercent    = 3.0;    // 0 = nonaktif; diabaikan jika Standar keranjang aktif
input double          InpCEmergencySLPercent   = 1.5;    // SL server darurat, 0 = nonaktif; diabaikan jika Standar aktif
input int             InpCMaxKunciSeconds      = 3600;   // 0 = nonaktif
input int             InpCReentryDelaySeconds  = 60;
input int             InpCKunciMinHoldSeconds  = 60;
input int             InpCKunciCooldownSeconds = 120;
input double          InpCMaxAtrRatio          = 2.0;    // 0 = nonaktif

input group "Tampilan"
input ENUM_THEME      InpTheme                 = THEME_DARK;
input ENUM_LANG       InpLanguage              = LANG_ID;
input int             InpPanelWidth            = 520;   // lebar panel (px)
input int             InpPanelX                = 10;
input int             InpPanelY                = 20;
input int             InpUiRefreshMs           = 500;
input bool            InpShowLines             = true;
input bool            InpFitChartToLines       = false;

input group "Notifikasi"
input bool            InpNotifyAlert           = true;
input bool            InpNotifyPush            = false;
input bool            InpNotifyEmail           = false;
input bool            InpNotifyOnKunci         = true;
input bool            InpNotifyOnFlip          = true;
input bool            InpNotifyOnEmergency     = true;
input bool            InpNotifyOnCycleEnd      = false;

input group "Suara & jurnal"
input string          InpSoundOnClose          = "ok.wav";
input string          InpSoundOnOpen           = "expert.wav";
input bool            InpJournal               = true;   // CSV di folder Common\Files

//--- konfigurasi kerja
struct Cfg
  {
   double marginUse;  int    slices;     double profitPct;   double lossPct;
   double kcTrigger;  double kcRatio;    int    kcSlices;    double kcReserve;
   double kcRecover;  double kcRelease;  bool   kcFlip;      double kcFlipBuf;
   int    maxSpread;  double minMarginLvl; double killPct;   double emSLPct;
   int    maxKcSec;   int    reentry;   int    kcMinHold;    int    kcCooldown;
   double atrRatio;   bool   kcEnable;   double kunciPct;
  };
Cfg    cfg;
string g_profileName = "";

//--- snapshot posisi (dihitung sekali per langkah)
struct Snap
  {
   int      mainCnt, kunciCnt;
   double   mainVol, kunciVol, mainPL, kunciPL, vwapMain, vwapAll, netVol;
   datetime oldest;
  };
Snap snap;

//--- palet warna
struct Pal { color panel, header, border, txt, dim, good, warn, bad, accent, barBg, btn; };
Pal pal;

CTrade trade;
long   g_chart = 0;
string g_pfx   = "";
string g_gv    = "";

const string COMMENT_MAIN  = "MU-main";
const string COMMENT_KUNCI = "MU-kunci";

datetime g_basketStart = 0, g_lastCloseTime = 0, g_lastSliceTime = 0, g_lastKunciTime = 0;
datetime g_kunciStart = 0, g_lastRelease = 0;
double   g_targetLots = 0, g_sliceLots = 0, g_kunciTargetLots = 0, g_kunciSliceLots = 0;
double   g_cycleRealized = 0, g_peakLots = 0;
double   g_startBal = 0;   // saldo sebelum posisi keranjang dibuka (acuan semua persen)
int      g_flipCount = 0;  // jumlah flip yang sudah berjalan pada keranjang ini
bool     g_kunciIsFlip = false, g_flipMode = false;
bool     g_lastCloseProfit = false, g_pendingTarget = false;   // penutupan terakhir = target profit tercapai
string   g_lastSignal = "";
string   g_lastAction = "idle", g_pendingClose = "";
string   g_log[5];
bool     g_paused = false, g_isKunci = false, g_kunciUsed = false;
bool     g_showLines = true, g_minimized = false;
ENUM_NYESER_DIR g_currentDir = NYESER_BUY, g_basketDir = NYESER_BUY;
int      g_atr = INVALID_HANDLE;
string   g_lvSig = "";
string   g_body[];
int      g_W = 520;
double   g_spreadEma = 0.0, g_spreadMult = 2.0;
datetime g_nextTry = 0;

struct Level { string key; double price; color clr; ENUM_LINE_STYLE style; string cap; };
Level g_lv[6];
int   g_lvN = 0;

#define PANEL_H 344

//+------------------------------------------------------------------+
string T(const string id, const string en) { return(InpLanguage == LANG_ID ? id : en); }

// saldo acuan: saldo sebelum posisi dibuka; jika belum ada keranjang, saldo saat ini
double BasketBalance()
  {
   return(g_startBal > 0.0 ? g_startBal : AccountInfoDouble(ACCOUNT_BALANCE));
  }

// jarak flip berikutnya (% saldo sebelum posisi): awal, awal x pengali, awal x pengali^2, ...
double FlipDistancePct()
  {
   if(!g_flipMode)
      return(cfg.kunciPct);
   return(cfg.kunciPct * MathPow(MathMax(1.0, InpFlipDistMultiplier), (double)g_flipCount));
  }

// jeda sebelum entry lagi: setelah target profit pakai InpReentryAfterTargetSec, selain itu ikut profil
int ReentryDelay()
  {
   return(g_lastCloseProfit ? MathMax(0, InpReentryAfterTargetSec) : cfg.reentry);
  }

//+------------------------------------------------------------------+
void SetCfg(double mu, int sl, double pp, double lp, double trig, double ratio, int kcsl, double res,
            double rec, double rel, bool flip, double fbuf, int spr, double mml, double kill,
            double emsl, int maxkc, int reent, int hold, int cool, double atr)
  {
   cfg.marginUse = mu;  cfg.slices = sl;  cfg.profitPct = pp;  cfg.lossPct = lp;
   cfg.kcTrigger = trig; cfg.kcRatio = ratio; cfg.kcSlices = kcsl; cfg.kcReserve = res;
   cfg.kcRecover = rec; cfg.kcRelease = rel; cfg.kcFlip = flip; cfg.kcFlipBuf = fbuf;
   cfg.maxSpread = spr; cfg.minMarginLvl = mml; cfg.killPct = kill; cfg.emSLPct = emsl;
   cfg.maxKcSec = maxkc; cfg.reentry = reent; cfg.kcMinHold = hold; cfg.kcCooldown = cool;
   cfg.atrRatio = atr;
  }

//+------------------------------------------------------------------+
void ApplyProfile()
  {
   switch(InpProfile)
     {
      case PROFILE_CONSERVATIVE:
         g_profileName = T("KONSERVATIF", "CONSERVATIVE");
         SetCfg(30, 3, 0.5, 0.5, 60, 0.6, 2, 30, 0.15, 25, false, 0.10, 0, 200, 3.0, 1.5, 3600, 60, 60, 120, 2.0);
         break;
      case PROFILE_MODERATE:
         g_profileName = T("MODERAT", "MODERATE");
         SetCfg(60, 4, 0.8, 0.8, 60, 0.8, 3, 40, 0.20, 25, false, 0.10, 0, 120, 5.0, 3.0, 7200, 30, 30, 60, 3.0);
         break;
      case PROFILE_AGGRESSIVE:
         g_profileName = T("AGRESIF", "AGGRESSIVE");
         SetCfg(95, 5, 1.0, 1.0, 60, 1.2, 3, 40, 0.20, 25, true, 0.10, 0, 0, 10.0, 5.0, 0, 0, 0, 0, 0);
         break;
      default:
         g_profileName = T("KUSTOM", "CUSTOM");
         SetCfg(InpCMarginUsagePercent, InpCSliceCount, InpCProfitBasketPercent, InpCLossLimitPercent,
                InpCKunciTriggerPercent, InpCKunciVolumeRatio, InpCKunciSliceCount, InpCKunciMarginReserve,
                InpCKunciRecoverPercent, InpCKunciReleasePercent, InpCKunciFlipToWinner, InpCKunciFlipBufferPct,
                InpCMaxSpreadPoints, InpCMinMarginLevel, InpCKillSwitchPercent, InpCEmergencySLPercent,
                InpCMaxKunciSeconds, InpCReentryDelaySeconds, InpCKunciMinHoldSeconds, InpCKunciCooldownSeconds,
                InpCMaxAtrRatio);
         break;
     }
   cfg.kcEnable = InpKunciEnable;

   // standar keranjang: menimpa nilai profil (bisa dimatikan lewat InpUseBasketStd = false)
   if(InpUseBasketStd)
     {
      cfg.profitPct = InpBasketProfitPct;
      cfg.lossPct   = InpBasketLossPct;
      cfg.kcFlip    = false;   // flip pemulihan lama diganti flip martingale
      cfg.killPct   = InpStdKillPct;
      cfg.emSLPct   = InpStdEmergencySLPct;
      g_profileName += T(" +STANDAR", " +STANDARD");
     }

   g_spreadMult = (InpProfile == PROFILE_CONSERVATIVE) ? 2.0 : (InpProfile == PROFILE_MODERATE ? 3.0 :
                   (InpProfile == PROFILE_AGGRESSIVE ? 0.0 : InpCSpreadSpikeMult));
  }

//+------------------------------------------------------------------+
bool ValidateConfig()
  {
   if(cfg.profitPct <= 0.0 || cfg.lossPct <= 0.0)
     { Print("Mesin Uang: profit% dan rugi% harus > 0."); return(false); }
   cfg.slices    = MathMax(1, cfg.slices);
   cfg.kcSlices  = MathMax(1, cfg.kcSlices);
   cfg.marginUse = MathMax(1.0, MathMin(100.0, cfg.marginUse));
   cfg.kcReserve = MathMax(0.0, MathMin(80.0, cfg.kcReserve));
   cfg.kcTrigger = MathMax(10.0, MathMin(95.0, cfg.kcTrigger));
   cfg.kcRatio   = MathMax(0.1, cfg.kcRatio);

   // ambang kunci dalam % saldo sebelum posisi
   if(InpUseBasketStd)
      cfg.kunciPct = InpKunciFlipPct;
   else
      cfg.kunciPct = cfg.lossPct * cfg.kcTrigger / 100.0;
   cfg.kunciPct = MathMax(0.1, cfg.kunciPct);

   if(cfg.kcEnable && AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      cfg.kcEnable = false;
      Print("Mesin Uang: akun bukan hedging, fitur kunci dimatikan.");
     }
   g_flipMode = (InpUseBasketStd && InpFlipMartingale && cfg.kcEnable);
   if(InpUseBasketStd && InpFlipMartingale && !cfg.kcEnable)
      Print("Mesin Uang: PERINGATAN flip martingale butuh akun hedging, flip dimatikan.");
   if(g_flipMode && InpFlipLotMultiplier < 1.0)
      Print("Mesin Uang: PERINGATAN pengali lot flip < 1.0, ini bukan martingale.");
   if(g_flipMode && InpFlipDistMultiplier < 1.0)
      Print("Mesin Uang: PERINGATAN pengali jarak flip < 1.0, dipakai 1.0.");
   if(g_flipMode)
     {
      double cum = 0.0;
      for(int f = 0; f < InpFlipMaxCount; f++)
        {
         double d = cfg.kunciPct * MathPow(MathMax(1.0, InpFlipDistMultiplier), (double)f);
         cum += d;
         if(cum >= cfg.lossPct)
           {
            Print("Mesin Uang: INFO flip ke-", f + 1, " (jarak ", DoubleToString(d, 1), "%) tidak akan sempat jalan: total rugi ",
                  DoubleToString(cum, 1), "% sudah mencapai batas rugi keranjang ", DoubleToString(cfg.lossPct, 1), "%.");
            break;
           }
        }
     }
   if(cfg.kcEnable && cfg.kcFlip && cfg.kcRatio <= 1.0)
      Print("Mesin Uang: PERINGATAN flip hampir tidak pernah aktif jika rasio kunci <= 1.0.");
   if(cfg.kcFlipBuf > cfg.kcRecover)
      Print("Mesin Uang: PERINGATAN buffer flip > target recovery.");
   if(cfg.killPct > 0.0 && cfg.killPct <= cfg.lossPct)
      Print("Mesin Uang: PERINGATAN kill switch <= batas rugi, kill switch akan lebih dulu aktif.");
   if(cfg.emSLPct > 0.0 && cfg.emSLPct <= cfg.kunciPct)
      Print("Mesin Uang: PERINGATAN SL darurat <= ambang kunci, kunci tidak akan sempat aktif.");
   if(cfg.kunciPct >= cfg.lossPct)
      Print("Mesin Uang: PERINGATAN ambang kunci >= batas rugi, kunci tidak akan sempat aktif.");
   return(true);
  }

//+------------------------------------------------------------------+
//| Tema                                                              |
//+------------------------------------------------------------------+
void ApplyTheme()
  {
   if(InpTheme == THEME_DARK)
     {
      pal.panel = C'14,18,28';   pal.header = C'0,90,140';  pal.border = C'0,150,220';
      pal.txt   = C'230,235,245'; pal.dim   = C'140,150,170'; pal.good  = C'0,200,120';
      pal.warn  = C'255,190,0';  pal.bad    = C'255,80,80';  pal.accent = C'0,170,255';
      pal.barBg = C'40,48,64';   pal.btn    = C'38,48,70';
     }
   else
     {
      pal.panel = C'245,247,250'; pal.header = C'30,120,190'; pal.border = C'30,120,190';
      pal.txt   = C'20,25,35';   pal.dim    = C'100,110,125'; pal.good  = C'0,150,80';
      pal.warn  = C'200,130,0';  pal.bad    = C'210,40,40';  pal.accent = C'0,120,200';
      pal.barBg = C'210,215,225'; pal.btn   = C'225,230,240';
     }
  }

//+------------------------------------------------------------------+
//| Log & notifikasi                                                  |
//+------------------------------------------------------------------+
void AddLog(const string msg)
  {
   for(int i = 4; i > 0; i--)
      g_log[i] = g_log[i - 1];
   g_log[0] = TimeToString(TimeTradeServer(), TIME_SECONDS) + " " + msg;
   g_lastAction = msg;
   Print("Mesin Uang: ", msg);
  }

// ev: 0 kunci, 1 flip, 2 darurat, 3 siklus selesai
void Notify(const int ev, const string msg)
  {
   bool on = (ev == 0 && InpNotifyOnKunci) || (ev == 1 && InpNotifyOnFlip) ||
             (ev == 2 && InpNotifyOnEmergency) || (ev == 3 && InpNotifyOnCycleEnd);
   if(!on)
      return;
   string full = "Mesin Uang " + _Symbol + ": " + msg;
   if(InpNotifyAlert)
      Alert(full);
   if(InpNotifyPush)
      SendNotification(full);
   if(InpNotifyEmail)
      SendMail("Mesin Uang", full);
  }

//+------------------------------------------------------------------+
void JournalWrite(const string reason, const double pl, const double lots, const int dur,
                  const ENUM_NYESER_DIR dir, const double balance)
  {
   if(!InpJournal)
      return;
   string fn = "MesinUang_" + IntegerToString(InpMagic) + "_" + _Symbol + ".csv";
   int h = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_COMMON, ';');
   if(h == INVALID_HANDLE)
      return;
   if(FileSize(h) == 0)
      FileWrite(h, "close_time", "symbol", "dir", "max_lots", "duration_s", "kunci_used", "pl", "pl_pct", "balance_before", "reason");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS), _Symbol,
             (dir == NYESER_BUY ? "BUY" : "SELL"), DoubleToString(lots, 2), IntegerToString(dur),
             (g_kunciUsed ? "1" : "0"), DoubleToString(pl, 2),
             DoubleToString(balance > 0 ? pl / balance * 100.0 : 0.0, 3), DoubleToString(balance, 2), reason);
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| State persistence                                                 |
//+------------------------------------------------------------------+
void SaveState()
  {
   GlobalVariableSet(g_gv + "dir", (double)g_basketDir);
   GlobalVariableSet(g_gv + "pg", g_isKunci ? 1.0 : 0.0);
   GlobalVariableSet(g_gv + "real", g_cycleRealized);
   GlobalVariableSet(g_gv + "start", (double)g_basketStart);
   GlobalVariableSet(g_gv + "pgstart", (double)g_kunciStart);
   GlobalVariableSet(g_gv + "used", g_kunciUsed ? 1.0 : 0.0);
   GlobalVariableSet(g_gv + "sbal", g_startBal);
   GlobalVariableSet(g_gv + "flips", (double)g_flipCount);
   GlobalVariableSet(g_gv + "kflip", g_kunciIsFlip ? 1.0 : 0.0);
  }

void ClearState()
  {
   string n[] = {"dir", "pg", "real", "start", "pgstart", "used", "sbal", "flips", "kflip"};
   for(int i = 0; i < ArraySize(n); i++)
      if(GlobalVariableCheck(g_gv + n[i]))
         GlobalVariableDel(g_gv + n[i]);
  }

void LoadState()
  {
   TakeSnapshot();
   if(snap.mainCnt + snap.kunciCnt == 0)
     {
      ClearState();
      return;
     }
   if(GlobalVariableCheck(g_gv + "dir"))
     {
      g_basketDir     = (ENUM_NYESER_DIR)(int)GlobalVariableGet(g_gv + "dir");
      g_isKunci       = GlobalVariableGet(g_gv + "pg") > 0.5;
      g_cycleRealized = GlobalVariableGet(g_gv + "real");
      g_basketStart   = (datetime)(long)GlobalVariableGet(g_gv + "start");
      g_kunciStart    = (datetime)(long)GlobalVariableGet(g_gv + "pgstart");
      g_kunciUsed     = GlobalVariableGet(g_gv + "used") > 0.5;
      g_startBal      = GlobalVariableGet(g_gv + "sbal");
      g_flipCount     = (int)GlobalVariableGet(g_gv + "flips");
      g_kunciIsFlip   = GlobalVariableGet(g_gv + "kflip") > 0.5;
     }
   else
     {
      double buyV = 0, sellV = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !OurSelected())
            continue;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            buyV += PositionGetDouble(POSITION_VOLUME);
         else
            sellV += PositionGetDouble(POSITION_VOLUME);
        }
      g_basketDir = (buyV >= sellV) ? NYESER_BUY : NYESER_SELL;
      g_isKunci   = (buyV > 0 && sellV > 0);
      g_kunciUsed = g_isKunci;
      g_kunciStart = TimeTradeServer();
     }
   if(g_startBal <= 0.0)
      g_startBal = AccountInfoDouble(ACCOUNT_BALANCE);   // cadangan jika state lama tidak punya saldo awal
   TakeSnapshot();
   g_currentDir  = g_basketDir;
   g_targetLots  = snap.mainVol;
   if(g_basketStart == 0)
      g_basketStart = snap.oldest;
   if(g_isKunci)
      g_kunciTargetLots = MathMax(snap.kunciVol, NormalizeVolume(snap.mainVol * (g_kunciIsFlip ? InpFlipLotMultiplier : cfg.kcRatio)));
   g_kunciSliceLots = NormalizeVolume(g_kunciTargetLots / MathMax(1, cfg.kcSlices));
   AddLog(T("state dipulihkan dari posisi terbuka", "state restored from open positions"));
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_chart = ChartID();
   g_W     = MathMax(380, InpPanelWidth);
   g_pfx   = "nyp" + IntegerToString(InpMagic) + "_";
   g_gv    = "NYP_" + IntegerToString(InpMagic) + "_" + _Symbol + "_";
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   ApplyProfile();
   if(!ValidateConfig())
      return(INIT_PARAMETERS_INCORRECT);

   g_currentDir = InpDirection;
   g_basketDir  = InpDirection;
   g_showLines  = InpShowLines;
   if(cfg.atrRatio > 0.0)
      g_atr = iATR(_Symbol, InpAtrTimeframe, 14);

   LoadState();
   ApplyTheme();
   BuildPanel();
   EventSetMillisecondTimer(MathMax(100, InpUiRefreshMs));
   AddLog("v2.30 " + T("mulai, profil ", "started, profile ") + g_profileName);
   RefreshUI();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveState();
   if(g_atr != INVALID_HANDLE)
      IndicatorRelease(g_atr);
   ObjectsDeleteAll(g_chart, g_pfx);
   if(InpFitChartToLines)
      ChartSetInteger(g_chart, CHART_SCALEFIX, false);
   ChartRedraw(g_chart);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   RunLogic();
  }

void OnTimer()
  {
   UpdateSpreadEma();
   RunLogic();
   ApplyEmergencySL();
   RefreshUI();
  }

void RunLogic()
  {
   ManageBasket();
   TakeSnapshot();
   MaybeOpenFullMargin();
   TakeSnapshot();
   MaybeOpenKunci();
  }

//+------------------------------------------------------------------+
//| Posisi                                                            |
//+------------------------------------------------------------------+
bool OurSelected()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return(false);
   return((long)PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

bool IsMainType(const long type)
  {
   return(g_basketDir == NYESER_BUY ? type == POSITION_TYPE_BUY : type == POSITION_TYPE_SELL);
  }

void TakeSnapshot()
  {
   ZeroMemory(snap);
   double absVol = 0.0, wAll = 0.0, wMain = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !OurSelected())
         continue;
      long     type  = PositionGetInteger(POSITION_TYPE);
      double   vol   = PositionGetDouble(POSITION_VOLUME);
      double   price = PositionGetDouble(POSITION_PRICE_OPEN);
      double   pl    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      datetime tm    = (datetime)PositionGetInteger(POSITION_TIME);

      snap.netVol += (type == POSITION_TYPE_BUY) ? vol : -vol;
      absVol += vol;
      wAll   += price * vol;
      if(snap.oldest == 0 || tm < snap.oldest)
         snap.oldest = tm;

      if(IsMainType(type))
        { snap.mainCnt++; snap.mainVol += vol; snap.mainPL += pl; wMain += price * vol; }
      else
        { snap.kunciCnt++; snap.kunciVol += vol; snap.kunciPL += pl; }
     }
   if(absVol > 0.0)
      snap.vwapAll = wAll / absVol;
   if(snap.mainVol > 0.0)
      snap.vwapMain = wMain / snap.mainVol;
  }

// mode: 0 semua, 1 sisi utama, 2 sisi kunci
bool ClosePositions(const int mode)
  {
   for(int attempt = 0; attempt < 3; attempt++)
     {
      bool any = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !OurSelected())
            continue;
         bool isMain = IsMainType(PositionGetInteger(POSITION_TYPE));
         if(mode == 1 && !isMain)
            continue;
         if(mode == 2 && isMain)
            continue;
         any = true;
         trade.PositionClose(t);
        }
      if(!any)
         return(true);
      TakeSnapshot();
      int left = (mode == 0) ? snap.mainCnt + snap.kunciCnt : (mode == 1 ? snap.mainCnt : snap.kunciCnt);
      if(left == 0)
         return(true);
      Sleep(150);
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool CloseBasket(const string reason, const bool targetHit = false)
  {
   TakeSnapshot();
   double balance = BasketBalance();
   double total   = snap.mainPL + snap.kunciPL + g_cycleRealized;
   double lots    = MathMax(g_peakLots, snap.mainVol + snap.kunciVol);
   int    dur     = (g_basketStart > 0) ? (int)(TimeTradeServer() - g_basketStart) : 0;
   ENUM_NYESER_DIR dir = g_basketDir;
   bool   hadKunci = g_isKunci;
   double kcWon = snap.kunciPL, mnWon = snap.mainPL;

   if(!ClosePositions(0))
     {
      g_pendingClose = reason;
      g_pendingTarget = targetHit;
      g_lastAction = T("gagal tutup, ulangi: ", "close failed, retrying: ") + reason;
      return(false);
     }

   JournalWrite(reason, total, lots, dur, dir, balance);
   if(StringLen(InpSoundOnClose) > 0)
      PlaySound(InpSoundOnClose);

   if(InpAutoSwitchDir)
     {
      // pemenang: jika sedang terkunci dan sisi kunci lebih untung, ikuti sisi kunci
      if(hadKunci && kcWon > mnWon)
         g_currentDir = (dir == NYESER_BUY) ? NYESER_SELL : NYESER_BUY;
      else
         g_currentDir = dir;
     }

   g_lastCloseTime = TimeTradeServer();
   g_lastCloseProfit = targetHit;
   g_pendingTarget = false;
   g_basketStart = 0; g_targetLots = 0; g_sliceLots = 0;
   g_kunciTargetLots = 0; g_kunciSliceLots = 0;
   g_isKunci = false; g_kunciUsed = false; g_cycleRealized = 0; g_peakLots = 0; g_startBal = 0;
   g_flipCount = 0; g_kunciIsFlip = false;
   g_pendingClose = "";
   ClearState();
   AddLog(reason + StringFormat("  P/L %.2f", total));
   Notify(StringFind(reason, "KILL") == 0 ? 2 : 3, reason + StringFormat("  P/L %.2f", total));

   if(StringFind(reason, "KILL") == 0)
     {
      g_paused = true;
      AddLog(T("EA dijeda oleh kill switch", "EA paused by kill switch"));
     }
   return(true);
  }

//+------------------------------------------------------------------+
void PromoteKunciToMain(const string why)
  {
   g_basketDir = (g_basketDir == NYESER_BUY) ? NYESER_SELL : NYESER_BUY;
   if(InpAutoSwitchDir)
      g_currentDir = g_basketDir;
   g_isKunci = false;
   g_kunciTargetLots = 0; g_kunciSliceLots = 0;
   g_lastRelease = TimeTradeServer();
   TakeSnapshot();
   g_targetLots = snap.mainVol;
   g_sliceLots  = 0;
   g_kunciIsFlip = false;
   AddLog(why + " -> " + (g_basketDir == NYESER_BUY ? "BUY" : "SELL"));
   SaveState();
  }

void StartKunci(const bool asFlip = false)
  {
   if(!cfg.kcEnable || snap.mainVol <= 0.0)
      return;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_kunciIsFlip = asFlip;
   if(asFlip)
      g_flipCount++;
   g_kunciTargetLots = NormalizeVolume(snap.mainVol * (asFlip ? InpFlipLotMultiplier : cfg.kcRatio));
   g_kunciSliceLots  = MathMax(minLot, NormalizeVolume(g_kunciTargetLots / MathMax(1, cfg.kcSlices)));
   g_isKunci    = true;
   g_kunciUsed  = true;
   g_kunciStart = TimeTradeServer();
   string what = asFlip ? T("flip martingale", "martingale flip") : T("kunci", "lock");
   AddLog(what + T(" mulai, target lot ", " started, target lot ") + DoubleToString(g_kunciTargetLots, 2));
   Notify(asFlip ? 1 : 0, what + " lot " + DoubleToString(g_kunciTargetLots, 2));
   SaveState();
  }

bool ReleaseKunciNow(const string why)
  {
   TakeSnapshot();
   double pl = snap.kunciPL;
   if(snap.kunciCnt > 0 && !ClosePositions(2))
     {
      AddLog(T("gagal lepas kunci", "failed to release lock"));
      return(false);
     }
   g_cycleRealized += pl;
   g_isKunci = false;
   g_kunciIsFlip = false;
   g_kunciTargetLots = 0; g_kunciSliceLots = 0;
   g_lastRelease = TimeTradeServer();
   AddLog(why);
   SaveState();
   return(true);
  }

//+------------------------------------------------------------------+
// Flip martingale: tutup semua posisi sisi rugi (rugi direalisasikan), sisi flip jadi utama.
// g_startBal tidak berubah, jadi target keranjang tetap N% dari saldo sebelum rugi tadi.
void FlipNow()
  {
   TakeSnapshot();
   double before = snap.mainPL;
   bool   ok     = ClosePositions(1);
   TakeSnapshot();
   g_cycleRealized += before - snap.mainPL;   // bagian yang sudah tertutup (juga bila hanya sebagian)
   if(!ok)
     {
      AddLog(T("flip: gagal tutup sisi rugi, ulangi", "flip: failed to close losing side, retrying"));
      return;
     }
   PromoteKunciToMain(T("flip martingale", "martingale flip"));
   Notify(1, StringFormat(T("flip ke %s, rugi terealisasi %.2f, lot %.2f", "flip to %s, realized loss %.2f, lot %.2f"),
          g_basketDir == NYESER_BUY ? "BUY" : "SELL", g_cycleRealized, snap.mainVol));
  }

//+------------------------------------------------------------------+
void ManageKunciRecovery(const double balance)
  {
   if(!g_isKunci)
      return;

   double mainEff  = snap.mainPL + g_cycleRealized;
   double combined = snap.mainPL + snap.kunciPL + g_cycleRealized;
   double combPct  = (balance > 0.0) ? combined / balance * 100.0 : 0.0;

   if(combPct >= cfg.kcRecover)
     {
      CloseBasket(T("recovery kunci ", "lock recovery ") + DoubleToString(combPct, 2) + "%");
      return;
     }

   // flip martingale: sisi flip sudah terbentuk -> tutup semua sisi rugi, sisi flip jadi utama
   if(g_kunciIsFlip)
     {
      double minLotF = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      bool built = snap.kunciVol > 0.0 &&
                   (snap.kunciVol >= g_kunciTargetLots - minLotF * 0.5 || snap.kunciCnt >= cfg.kcSlices);
      if(built)
         FlipNow();
      return;
     }

   if(cfg.kcFlip && snap.kunciVol > 0.0)
     {
      double need = -mainEff + balance * (cfg.kcFlipBuf / 100.0);
      if(need > 0.0 && snap.kunciPL >= need)
        {
         double mp = snap.mainPL;
         if(ClosePositions(1))
           {
            g_cycleRealized += mp;
            PromoteKunciToMain(T("flip ke pemenang", "flip to winner"));
            Notify(1, T("flip arah", "direction flip"));
           }
         return;
        }
     }

   // lepas kunci bila rugi utama sudah mereda (histeresis + durasi minimum)
   double releasePct = -(cfg.lossPct * (cfg.kcRelease / 100.0));
   double mainPct    = (balance > 0.0) ? mainEff / balance * 100.0 : 0.0;
   bool   heldEnough = (TimeTradeServer() - g_kunciStart) >= cfg.kcMinHold;
   if(snap.kunciVol > 0.0 && mainPct > releasePct && heldEnough)
      ReleaseKunciNow(T("kunci dilepas, lanjut arah utama", "lock released, continue main"));
  }

//+------------------------------------------------------------------+
void ManageBasket()
  {
   TakeSnapshot();
   int total = snap.mainCnt + snap.kunciCnt;

   if(g_pendingClose != "")
     {
      CloseBasket(g_pendingClose, g_pendingTarget);
      return;
     }

   if(total == 0)
     {
      if(g_basketStart != 0)
        {
         AddLog(T("posisi hilang (SL/manual)", "positions gone (SL/manual)"));
         g_lastCloseTime = TimeTradeServer();
         g_lastCloseProfit = false;
        }
      g_basketStart = 0; g_isKunci = false; g_kunciUsed = false;
      g_cycleRealized = 0; g_peakLots = 0; g_targetLots = 0; g_sliceLots = 0; g_startBal = 0;
      g_flipCount = 0; g_kunciIsFlip = false;
      g_kunciTargetLots = 0; g_kunciSliceLots = 0;
      ClearState();
      return;
     }

   if(g_basketStart == 0)
      g_basketStart = (snap.oldest > 0 ? snap.oldest : TimeTradeServer());

   // semua persen dihitung terhadap saldo sebelum posisi dibuka
   double balance = BasketBalance();
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0.0)
      return;

   // kill switch equity
   if(cfg.killPct > 0.0 && equity <= balance * (1.0 - cfg.killPct / 100.0))
     {
      CloseBasket("KILL SWITCH " + DoubleToString((balance - equity) / balance * 100.0, 2) + "%");
      return;
     }

   // sisi utama hilang (kena SL darurat / ditutup manual) -> kunci jadi utama
   if(snap.mainVol <= 0.0 && snap.kunciVol > 0.0)
     {
      PromoteKunciToMain(T("sisi utama hilang", "main side lost"));
      return;
     }

   double totalPL   = snap.mainPL + snap.kunciPL + g_cycleRealized;
   double profitPct = totalPL / balance * 100.0;
   int    elapsed   = (int)(TimeTradeServer() - g_basketStart);

   if(profitPct >= cfg.profitPct)
     { CloseBasket(g_isKunci ? T("keranjang profit (setelah kunci)", "basket profit (after lock)")
                             : T("keranjang profit", "basket profit"), true); return; }
   if(profitPct <= -cfg.lossPct)
     { CloseBasket(T("batas rugi", "loss limit")); return; }
   if(InpMaxBasketSeconds > 0 && elapsed >= InpMaxBasketSeconds)
     { CloseBasket(T("batas detik keranjang", "basket time limit")); return; }
   if(g_isKunci && cfg.maxKcSec > 0 && (TimeTradeServer() - g_kunciStart) >= cfg.maxKcSec)
     { CloseBasket(T("batas waktu kunci", "lock time limit")); return; }

   if(cfg.kcEnable && !g_isKunci && snap.mainVol > 0.0
      && (g_flipMode || g_lastRelease == 0 || (TimeTradeServer() - g_lastRelease) >= cfg.kcCooldown))
     {
      double trig = -FlipDistancePct();
      if(g_flipMode)
        {
         // ambang dihitung dari rugi sisi utama saat ini (rugi yang sudah terealisasi tidak dihitung lagi)
         double legPct = snap.mainPL / balance * 100.0;
         if(legPct <= trig && g_flipCount < InpFlipMaxCount)
           {
            StartKunci(true);
            TakeSnapshot();
           }
        }
      else if(profitPct <= trig)
        {
         StartKunci();
         TakeSnapshot();
        }
     }

   ManageKunciRecovery(balance);
  }

//+------------------------------------------------------------------+
//| Lot & order                                                       |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   int digits = (step >= 1.0 ? 0 : (int)MathRound(-MathLog10(step)));
   return(NormalizeDouble(lots, digits));
  }

double FullMarginLots(const ENUM_ORDER_TYPE type, const bool forKunci)
  {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double marginOneLot = 0.0;
   if(!OrderCalcMargin(type, _Symbol, 1.0, price, marginOneLot) || marginOneLot <= 0.0)
      return(0.0);
   double free  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double usage = cfg.marginUse / 100.0;
   if(!forKunci && cfg.kcEnable)
      usage *= (1.0 - cfg.kcReserve / 100.0);
   if(forKunci && g_kunciIsFlip)
      usage = InpFlipMarginUsePct / 100.0;
   return(NormalizeVolume((free * usage) / marginOneLot));
  }

int ServerSeconds()
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   return(dt.sec);
  }

void UpdateSpreadEma()
  {
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sp <= 0)
      return;
   if(g_spreadEma <= 0.0)
      g_spreadEma = (double)sp;
   else
      g_spreadEma = g_spreadEma * 0.995 + (double)sp * 0.005;
  }

bool SpreadOK()
  {
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(cfg.maxSpread > 0 && sp > cfg.maxSpread)
      return(false);
   if(g_spreadMult > 0.0 && g_spreadEma > 0.0 && (double)sp > g_spreadEma * g_spreadMult + 1.0)
      return(false);
   return(true);
  }

string TradeBlocker()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(T("Tombol Algo Trading terminal OFF", "Terminal Algo Trading button is OFF"));
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return(T("Centang 'Allow Algo Trading' di properti EA", "Tick 'Allow Algo Trading' in EA properties"));
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return(T("Akun/server melarang EA trading", "Account/server disallows EA trading"));
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return(T("Akun tidak boleh trading (password investor?)", "Account trading disabled (investor password?)"));
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      return(T("Simbol belum bisa ditradingkan (pasar tutup?)", "Symbol not tradable now (market closed?)"));
   return("");
  }

bool SessionOK()
  {
   if(!InpUseSession)
      return(true);
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   if(InpSessionStartHour <= InpSessionEndHour)
      return(dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
   return(dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
  }

bool VolatilityOK()
  {
   if(cfg.atrRatio <= 0.0 || g_atr == INVALID_HANDLE)
      return(true);
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(g_atr, 0, 0, 50, b) != 50)
      return(true);
   double s = 0.0;
   for(int i = 1; i < 50; i++)
      s += b[i];
   double avg = s / 49.0;
   if(avg <= 0.0)
      return(true);
   return(b[0] / avg <= cfg.atrRatio);
  }

bool MarginLevelOK()
  {
   if(cfg.minMarginLvl <= 0.0 || AccountInfoDouble(ACCOUNT_MARGIN) <= 0.0)
      return(true);
   return(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) >= cfg.minMarginLvl);
  }

bool OpenSlice(const ENUM_ORDER_TYPE type, const double lots, const bool kunci)
  {
   trade.SetExpertMagicNumber(InpMagic);
   string comment = kunci ? COMMENT_KUNCI : COMMENT_MAIN;
   bool ok = (type == ORDER_TYPE_BUY) ? trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, comment)
                                      : trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, comment);
   if(ok)
     {
      if(StringLen(InpSoundOnOpen) > 0)
         PlaySound(InpSoundOnOpen);
      if(kunci)
         g_lastKunciTime = TimeTradeServer();
      else
         g_lastSliceTime = TimeTradeServer();
      if(g_basketStart == 0)
         g_basketStart = TimeTradeServer();
      TakeSnapshot();
      g_peakLots = MathMax(g_peakLots, snap.mainVol + snap.kunciVol);
      g_lastAction = (kunci ? "kunci " : T("tiket ", "ticket "))
                     + IntegerToString(kunci ? snap.kunciCnt : snap.mainCnt) + "/"
                     + IntegerToString(kunci ? cfg.kcSlices : cfg.slices) + "  lot " + DoubleToString(lots, 2);
      SaveState();
     }
   else
     {
      AddLog(T("gagal order ", "order failed ") + IntegerToString(trade.ResultRetcode()) + " "
             + trade.ResultRetcodeDescription());
      g_nextTry = TimeTradeServer() + 5;
     }
   return(ok);
  }

//+------------------------------------------------------------------+
// Arah entry dari kotak (candle) tertutup di sebelah kiri candle yang sedang berjalan.
//  CANDLE   : candle naik -> BUY, turun -> SELL
//  BREAKOUT : close menembus high/low N bar sebelumnya -> ikut arah tembusan
//  REVERSAL : candle penolakan (ekor panjang) -> arah berlawanan dengan ekor
//  AUTO     : reversal > breakout > candle
bool EntrySignal(ENUM_NYESER_DIR &dir, string &why)
  {
   int n    = MathMax(2, InpBreakoutBars);
   int need = n + 3;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpSignalTF, 0, need, r) < need)
      return(false);

   ENUM_ENTRY_MODE m = InpEntryMode;
   double range = r[1].high - r[1].low;   // r[1] = kotak kiri (candle tertutup terakhir)

   if((m == ENTRY_REVERSAL || m == ENTRY_AUTO) && range > 0.0)
     {
      double ratio  = MathMax(0.51, MathMin(0.95, InpPinWickRatio));
      double upWick = r[1].high - MathMax(r[1].open, r[1].close);
      double dnWick = MathMin(r[1].open, r[1].close) - r[1].low;
      if(dnWick / range >= ratio)
        { dir = NYESER_BUY;  why = T("reversal: ekor bawah panjang", "reversal: long lower wick"); return(true); }
      if(upWick / range >= ratio)
        { dir = NYESER_SELL; why = T("reversal: ekor atas panjang", "reversal: long upper wick"); return(true); }
     }

   if(m == ENTRY_BREAKOUT || m == ENTRY_AUTO)
     {
      double hh = -DBL_MAX, ll = DBL_MAX;
      for(int i = 2; i <= n + 1; i++)
        { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
      if(r[1].close > hh)
        { dir = NYESER_BUY;  why = T("breakout naik", "breakout up"); return(true); }
      if(r[1].close < ll)
        { dir = NYESER_SELL; why = T("breakout turun", "breakout down"); return(true); }
     }

   if(m == ENTRY_CANDLE || m == ENTRY_AUTO)
     {
      if(r[1].close > r[1].open)
        { dir = NYESER_BUY;  why = T("kotak kiri naik", "left candle up"); return(true); }
      if(r[1].close < r[1].open)
        { dir = NYESER_SELL; why = T("kotak kiri turun", "left candle down"); return(true); }
     }
   return(false);   // tidak ada sinyal (doji / belum ada breakout atau reversal)
  }

//+------------------------------------------------------------------+
void MaybeOpenFullMargin()
  {
   if(g_isKunci || g_pendingClose != "")
      return;
   if(!InpEnableTrading)
     { g_lastAction = "InpEnableTrading = false"; return; }
   if(g_paused)
     { g_lastAction = T("EA dijeda, tekan LANJUT", "EA paused, press RESUME"); return; }
   string blk = TradeBlocker();
   if(blk != "")
     { g_lastAction = blk; return; }
   if(TimeTradeServer() < g_nextTry)
      return;

   ENUM_ORDER_TYPE type = (g_currentDir == NYESER_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   int    slices = cfg.slices;
   int    total  = snap.mainCnt + snap.kunciCnt;

   if(total == 0)
     {
      datetime now = TimeTradeServer();
      if(g_lastCloseTime > 0 && ReentryDelay() > 0 && (now - g_lastCloseTime) < ReentryDelay())
        { g_lastAction = T("tunggu jeda re-entry", "waiting re-entry delay"); return; }
      if(InpEntryAtSecond00 && ServerSeconds() != 0 && g_lastCloseTime == 0)
        { g_lastAction = T("tunggu detik 00", "waiting second 00"); return; }
      if(!SessionOK())
        { g_lastAction = T("di luar sesi trading", "outside trading session"); return; }
      if(!SpreadOK())
        {
         g_lastAction = StringFormat(T("spread %d terlalu lebar (rata2 %.0f)", "spread %d too wide (avg %.0f)"),
                                     (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), g_spreadEma);
         return;
        }
      if(!VolatilityOK())
        { g_lastAction = T("volatilitas (ATR) terlalu tinggi", "volatility (ATR) too high"); return; }
      if(!MarginLevelOK())
        { g_lastAction = T("margin level terlalu rendah", "margin level too low"); return; }

      // arah entry mengikuti sinyal; FIXED = ikut input arah dan tombol
      g_lastSignal = "";
      if(InpEntryMode != ENTRY_FIXED)
        {
         ENUM_NYESER_DIR sigDir = g_currentDir;
         string sigWhy = "";
         if(EntrySignal(sigDir, sigWhy))
           {
            g_currentDir = sigDir;
            type = (g_currentDir == NYESER_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            g_lastSignal = sigWhy;
           }
         else if(InpEntryMode == ENTRY_BREAKOUT || InpEntryMode == ENTRY_REVERSAL)
           { g_lastAction = T("menunggu sinyal breakout/reversal", "waiting for breakout/reversal signal"); return; }
        }
      g_basketDir  = g_currentDir;
      g_targetLots = FullMarginLots(type, false);
      g_sliceLots  = MathMax(minLot, NormalizeVolume(g_targetLots / slices));
      if(g_targetLots <= 0.0 || g_sliceLots <= 0.0)
        { g_lastAction = T("lot full margin = 0", "full margin lot = 0"); return; }
      g_cycleRealized = 0; g_peakLots = 0; g_kunciUsed = false; g_lastRelease = 0;
      g_flipCount = 0; g_kunciIsFlip = false;
      g_startBal = AccountInfoDouble(ACCOUNT_BALANCE);   // saldo sebelum posisi dibuka
      if(OpenSlice(type, g_sliceLots, false))
        {
         g_lastCloseTime = 0;
         if(g_lastSignal != "")
            AddLog(g_lastSignal + " -> " + (g_basketDir == NYESER_BUY ? "BUY" : "SELL"));
        }
      return;
     }

   if(snap.mainCnt >= slices)
      return;
   if(!MarginLevelOK() || !SpreadOK())
      return;

   if(g_targetLots <= 0.0)
     {
      g_targetLots = NormalizeVolume(snap.mainVol + FullMarginLots(type, false));
      int remain = slices - snap.mainCnt;
      g_sliceLots = (remain > 0) ? NormalizeVolume((g_targetLots - snap.mainVol) / remain) : minLot;
     }
   if(snap.mainVol >= g_targetLots - (minLot * 0.5))
      return;
   if(InpSliceDelaySeconds > 0 && g_lastSliceTime > 0
      && (TimeTradeServer() - g_lastSliceTime) < InpSliceDelaySeconds)
      return;
   if(InpSliceDelaySeconds <= 0 && g_lastSliceTime == TimeTradeServer())
      return;

   double remaining = NormalizeVolume(g_targetLots - snap.mainVol);
   double lots = (snap.mainCnt == slices - 1) ? remaining : MathMin(g_sliceLots, remaining);
   double afford = FullMarginLots(type, false);
   if(afford < minLot || lots < minLot)
      return;
   lots = NormalizeVolume(MathMin(lots, afford));
   if(lots < minLot)
      return;
   OpenSlice(type, lots, false);
  }

//+------------------------------------------------------------------+
void MaybeOpenKunci()
  {
   if(!InpEnableTrading || !cfg.kcEnable || !g_isKunci || g_pendingClose != "")
      return;

   ENUM_ORDER_TYPE type = (g_basketDir == NYESER_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   int    slices = cfg.kcSlices;

   if(g_kunciTargetLots <= 0.0)
      StartKunci();
   if(snap.kunciVol >= g_kunciTargetLots - (minLot * 0.5) || snap.kunciCnt >= slices)
      return;
   if(InpKunciSliceDelaySeconds > 0 && g_lastKunciTime > 0
      && (TimeTradeServer() - g_lastKunciTime) < InpKunciSliceDelaySeconds)
      return;

   double remaining = NormalizeVolume(g_kunciTargetLots - snap.kunciVol);
   double lots = (snap.kunciCnt == slices - 1) ? remaining : MathMin(g_kunciSliceLots, remaining);
   double afford = FullMarginLots(type, true);
   if(afford < minLot || lots < minLot)
     {
      if(g_kunciIsFlip && snap.kunciVol >= minLot)
        {
         g_kunciTargetLots = snap.kunciVol;   // margin habis: selesaikan flip dengan lot yang sudah terbentuk
         return;
        }
      if(g_kunciIsFlip)
        {
         // sisi flip sama sekali tidak terbuka: batalkan flip
         g_isKunci = false; g_kunciIsFlip = false; g_kunciTargetLots = 0; g_kunciSliceLots = 0;
         g_lastRelease = TimeTradeServer();
         AddLog(T("flip batal: margin tidak cukup", "flip cancelled: not enough margin"));
         SaveState();
         return;
        }
      g_lastAction = T("kunci: margin sisa kurang", "lock: not enough free margin");
      return;
     }
   lots = NormalizeVolume(MathMin(lots, afford));
   if(lots < minLot)
      return;
   OpenSlice(type, lots, true);
  }

//+------------------------------------------------------------------+
//| SL darurat di server (hanya sisi utama, saat belum terkunci)      |
//+------------------------------------------------------------------+
void ApplyEmergencySL()
  {
   if(cfg.emSLPct <= 0.0 || g_isKunci || snap.mainVol <= 0.0 || g_pendingClose != "")
      return;
   double balance = BasketBalance();
   if(balance <= 0.0)
      return;

   ENUM_ORDER_TYPE type = (g_basketDir == NYESER_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double mark = (type == ORDER_TYPE_BUY) ? bid : ask;
   double mpp = 0.0;
   if(!MoneyPerPriceMove(type, snap.mainVol, snap.vwapMain > 0 ? snap.vwapMain : mark, mpp) || mpp <= 0.0)
      return;

   double target = -balance * cfg.emSLPct / 100.0 - g_cycleRealized;   // batas total, rugi terealisasi ikut dihitung
   double sl = NormalizeDouble(PriceForTargetMoney(type, mark, snap.mainPL, target, mpp), _Digits);
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(sl <= 0.0)
      return;
   if(type == ORDER_TYPE_BUY  && sl >= bid - stopLvl)
      return;
   if(type == ORDER_TYPE_SELL && sl <= ask + stopLvl)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !OurSelected() || !IsMainType(PositionGetInteger(POSITION_TYPE)))
         continue;
      if(MathAbs(PositionGetDouble(POSITION_SL) - sl) > 10 * _Point)
         trade.PositionModify(t, sl, PositionGetDouble(POSITION_TP));
     }
  }

//+------------------------------------------------------------------+
//| Model harga untuk garis level                                     |
//+------------------------------------------------------------------+
bool MoneyPerPriceMove(const ENUM_ORDER_TYPE type, const double volume, const double openPrice, double &mpp)
  {
   mpp = 0.0;
   if(volume <= 0.0 || openPrice <= 0.0)
      return(false);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return(false);

   double probe = openPrice + 100.0 * point;
   double profitPlus = 0.0;
   if(!OrderCalcProfit(type, _Symbol, volume, openPrice, probe, profitPlus))
     {
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return(false);
      mpp = (volume * tickValue) / tickSize;
      return(mpp > 0.0);
     }
   double dist = probe - openPrice;
   if(MathAbs(dist) < point * 0.1)
      return(false);
   mpp = profitPlus / dist;
   if(type == ORDER_TYPE_SELL)
      mpp = -mpp;
   return(MathAbs(mpp) > 0.0);
  }

double PriceForTargetMoney(const ENUM_ORDER_TYPE type, const double markPrice, const double currentProfit,
                           const double targetMoney, const double mppAbs)
  {
   double signedMpp = (type == ORDER_TYPE_BUY) ? mppAbs : -mppAbs;
   if(MathAbs(signedMpp) < 1e-12)
      return(markPrice);
   return(markPrice + (targetMoney - currentProfit) / signedMpp);
  }

double StopOutTargetMoney(const double usedMargin, const double currentProfit)
  {
   double soLevel = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   long   soMode  = AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double equityFlat = equity - currentProfit;
   double equityAtSO = 0.0;
   if(soMode == ACCOUNT_STOPOUT_MODE_MONEY)
      equityAtSO = soLevel;
   else
     {
      if(usedMargin <= 0.0)
         return(0.0);
      equityAtSO = usedMargin * soLevel / 100.0;
     }
   return(equityAtSO - equityFlat);
  }

bool PrepareLineModel(ENUM_ORDER_TYPE &type, double &volume, double &mark, double &open,
                      double &profit, double &margin)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   int total = snap.mainCnt + snap.kunciCnt;
   if(total > 0)
     {
      if(MathAbs(snap.netVol) < minLot * 0.5)
         return(false);                    // terkunci penuh, garis tidak bermakna
      profit = snap.mainPL + snap.kunciPL + g_cycleRealized;
      type   = (snap.netVol > 0.0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      volume = MathAbs(snap.netVol);
      open   = snap.vwapAll;
      mark   = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(open <= 0.0)
         open = mark;
      margin = AccountInfoDouble(ACCOUNT_MARGIN);
      if(margin <= 0.0)
         OrderCalcMargin(type, _Symbol, volume, open, margin);
      return(true);
     }
   type   = (g_currentDir == NYESER_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   volume = FullMarginLots(type, false);
   if(volume <= 0.0)
      volume = minLot;
   mark   = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   open   = mark;
   profit = 0.0;
   if(!OrderCalcMargin(type, _Symbol, volume, open, margin))
      margin = 0.0;
   return(volume > 0.0 && mark > 0.0);
  }

void AddLevel(const string key, const double price, const color clr, const ENUM_LINE_STYLE style, const string cap)
  {
   if(price <= 0.0 || g_lvN >= 6)
      return;
   g_lv[g_lvN].key = key; g_lv[g_lvN].price = price; g_lv[g_lvN].clr = clr;
   g_lv[g_lvN].style = style; g_lv[g_lvN].cap = cap;
   g_lvN++;
  }

void UpdateTargetLines()
  {
   g_lvN = 0;
   if(!g_showLines)
     {
      DrawLevels();
      return;
     }
   ENUM_ORDER_TYPE type;
   double volume = 0, mark = 0, open = 0, profit = 0, margin = 0;
   if(PrepareLineModel(type, volume, mark, open, profit, margin))
     {
      double mpp = 0.0;
      double balance = BasketBalance();   // saldo sebelum posisi (atau saldo saat ini jika belum ada keranjang)
      if(MoneyPerPriceMove(type, volume, open, mpp) && mpp > 0.0 && balance > 0.0)
        {
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double tpRef = g_isKunci ? MathMin(cfg.profitPct, cfg.kcRecover) : cfg.profitPct;
         double tpP = NormalizeDouble(PriceForTargetMoney(type, mark, profit, balance * tpRef / 100.0, mpp), digits);
         double slP = NormalizeDouble(PriceForTargetMoney(type, mark, profit, -balance * cfg.lossPct / 100.0, mpp), digits);
         double soMoney = StopOutTargetMoney(margin, profit);
         double soP = NormalizeDouble(PriceForTargetMoney(type, mark, profit, soMoney, mpp), digits);

         AddLevel("tp", tpP, pal.good, STYLE_SOLID,
                  (g_isKunci ? "Recovery " : "TP ") + DoubleToString(tpRef, 2) + "%  " + DoubleToString(tpP, digits));
         AddLevel("sl", slP, pal.bad, STYLE_SOLID,
                  T("Rugi ", "Loss ") + DoubleToString(cfg.lossPct, 2) + "%  " + DoubleToString(slP, digits));

         // garis Pra-Stop Out: lebih dekat ke harga daripada SO, sejauh buffer margin level
         if(InpShowPreSOLine)
           {
            double preMoney = soMoney + margin * InpPreSOBufferLevel / 100.0;
            if(preMoney < profit)   // hanya jika titik pra-SO masih di depan harga
              {
               double psP = NormalizeDouble(PriceForTargetMoney(type, mark, profit, preMoney, mpp), digits);
               AddLevel("ps", psP, pal.warn, STYLE_DASHDOT, T("Pra-SO ", "Pre-SO ") + DoubleToString(psP, digits));
              }
           }
         if(InpShowSOLine)
            AddLevel("so", soP, clrOrange, STYLE_DASH, "SO " + DoubleToString(soP, digits));

         if(!g_isKunci && cfg.kcEnable && (!g_flipMode || g_flipCount < InpFlipMaxCount))
           {
            double kcMoney = -balance * FlipDistancePct() / 100.0;
            if(g_flipMode)
               kcMoney += g_cycleRealized;   // ambang flip dihitung dari rugi sisi utama saat ini
            double kcP = NormalizeDouble(PriceForTargetMoney(type, mark, profit, kcMoney, mpp), digits);
            AddLevel("kc", kcP, pal.accent, STYLE_DOT, (g_flipMode ? "Flip " + IntegerToString(g_flipCount + 1) + " " : T("kunci ", "lock ")) + DoubleToString(FlipDistancePct(), 1) + "%  " + DoubleToString(kcP, digits));
           }
         if(g_isKunci && cfg.kcFlip)
           {
            double flP = NormalizeDouble(PriceForTargetMoney(type, mark, profit,
                         balance * cfg.kcFlipBuf / 100.0, mpp), digits);
            AddLevel("fl", flP, pal.warn, STYLE_DASHDOT, "Flip " + DoubleToString(flP, digits));
           }
        }
     }
   DrawLevels();
  }

//+------------------------------------------------------------------+
void DelLevel(const string key)
  {
   ObjectDelete(g_chart, g_pfx + "L_" + key);
   ObjectDelete(g_chart, g_pfx + "T_" + key);
  }

void DrawOne(const Level &lv, const double labelPrice, const datetime tLabel)
  {
   string ln = g_pfx + "L_" + lv.key;
   string tn = g_pfx + "T_" + lv.key;
   if(ObjectFind(g_chart, ln) < 0)
      ObjectCreate(g_chart, ln, OBJ_HLINE, 0, 0, lv.price);
   ObjectSetDouble(g_chart, ln, OBJPROP_PRICE, lv.price);
   ObjectSetInteger(g_chart, ln, OBJPROP_COLOR, lv.clr);
   ObjectSetInteger(g_chart, ln, OBJPROP_STYLE, lv.style);
   ObjectSetInteger(g_chart, ln, OBJPROP_WIDTH, lv.style == STYLE_SOLID ? 2 : 1);
   ObjectSetInteger(g_chart, ln, OBJPROP_BACK, false);
   ObjectSetInteger(g_chart, ln, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, ln, OBJPROP_HIDDEN, true);
   ObjectSetString(g_chart, ln, OBJPROP_TOOLTIP, lv.cap);

   if(ObjectFind(g_chart, tn) < 0)
      ObjectCreate(g_chart, tn, OBJ_TEXT, 0, tLabel, labelPrice);
   ObjectMove(g_chart, tn, 0, tLabel, labelPrice);
   ObjectSetInteger(g_chart, tn, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(g_chart, tn, OBJPROP_FONTSIZE, 9);
   ObjectSetString(g_chart, tn, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(g_chart, tn, OBJPROP_COLOR, lv.clr);
   ObjectSetInteger(g_chart, tn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, tn, OBJPROP_HIDDEN, true);
   ObjectSetString(g_chart, tn, OBJPROP_TEXT, "  " + lv.cap);
  }

void DrawLevels()
  {
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t1 <= 0)
      t1 = TimeCurrent();
   string sig = IntegerToString((long)t1) + "|" + (g_showLines ? "1" : "0") + "|";
   for(int i = 0; i < g_lvN; i++)
      sig += g_lv[i].key + DoubleToString(g_lv[i].price, _Digits) + ";";
   if(sig == g_lvSig)
      return;
   g_lvSig = sig;

   string keys[] = {"tp", "sl", "ps", "so", "kc", "fl"};
   for(int k = 0; k < ArraySize(keys); k++)
     {
      bool used = false;
      for(int i = 0; i < g_lvN; i++)
         if(g_lv[i].key == keys[k])
            used = true;
      if(!used)
         DelLevel(keys[k]);
     }
   if(g_lvN == 0)
      return;

   int idx[];
   ArrayResize(idx, g_lvN);
   for(int i = 0; i < g_lvN; i++)
      idx[i] = i;
   for(int a = 0; a < g_lvN - 1; a++)
      for(int b = 0; b < g_lvN - 1 - a; b++)
         if(g_lv[idx[b]].price > g_lv[idx[b + 1]].price)
           { int tmp = idx[b]; idx[b] = idx[b + 1]; idx[b + 1] = tmp; }

   double range = ChartGetDouble(g_chart, CHART_PRICE_MAX) - ChartGetDouble(g_chart, CHART_PRICE_MIN);
   if(range <= 0.0)
      range = _Point * 100.0;
   double sep = range * 0.04;
   double prev = -DBL_MAX;
   datetime tl = t1 + PeriodSeconds() * 2;
   for(int j = 0; j < g_lvN; j++)
     {
      int i = idx[j];
      double lp = g_lv[i].price;
      if(prev > -DBL_MAX && lp < prev + sep)
         lp = prev + sep;
      prev = lp;
      DrawOne(g_lv[i], lp, tl);
     }
   if(InpFitChartToLines)
      FitChartLevels();
  }

void FitChartLevels()
  {
   double lo = DBL_MAX, hi = -DBL_MAX;
   for(int i = 0; i < g_lvN; i++)
     { lo = MathMin(lo, g_lv[i].price); hi = MathMax(hi, g_lv[i].price); }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   lo = MathMin(lo, bid); hi = MathMax(hi, bid);
   double pad = (hi - lo) * 0.15;
   if(pad <= 0.0)
      pad = _Point * 50.0;
   ChartSetInteger(g_chart, CHART_SCALEFIX, true);
   ChartSetDouble(g_chart, CHART_FIXED_MIN, lo - pad);
   ChartSetDouble(g_chart, CHART_FIXED_MAX, hi + pad);
  }

//+------------------------------------------------------------------+
//| Panel UI                                                          |
//+------------------------------------------------------------------+
void AddBody(const string n)
  {
   for(int i = 0; i < ArraySize(g_body); i++)
      if(g_body[i] == n)
         return;
   int sz = ArraySize(g_body);
   ArrayResize(g_body, sz + 1);
   g_body[sz] = n;
  }

void MkRect(const string n, const int x, const int y, const int w, const int h,
            const color bg, const color bd, const bool body = true)
  {
   string nm = g_pfx + n;
   if(ObjectFind(g_chart, nm) < 0)
      ObjectCreate(g_chart, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(g_chart, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(g_chart, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(g_chart, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(g_chart, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(g_chart, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(g_chart, nm, OBJPROP_COLOR, bd);
   ObjectSetInteger(g_chart, nm, OBJPROP_BACK, false);
   ObjectSetInteger(g_chart, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, nm, OBJPROP_HIDDEN, true);
   if(body)
      AddBody(n);
  }

void MkLabel(const string n, const int x, const int y, const int size, const color clr, const bool body = true)
  {
   string nm = g_pfx + n;
   if(ObjectFind(g_chart, nm) < 0)
      ObjectCreate(g_chart, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(g_chart, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(g_chart, nm, OBJPROP_FONTSIZE, size);
   ObjectSetString(g_chart, nm, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(g_chart, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(g_chart, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, nm, OBJPROP_HIDDEN, true);
   if(body)
      AddBody(n);
  }

void MkButton(const string n, const int x, const int y, const int w, const int h, const string txt,
              const bool body = true)
  {
   string nm = g_pfx + n;
   if(ObjectFind(g_chart, nm) < 0)
      ObjectCreate(g_chart, nm, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(g_chart, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(g_chart, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(g_chart, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(g_chart, nm, OBJPROP_BGCOLOR, pal.btn);
   ObjectSetInteger(g_chart, nm, OBJPROP_BORDER_COLOR, pal.border);
   ObjectSetInteger(g_chart, nm, OBJPROP_COLOR, pal.txt);
   ObjectSetInteger(g_chart, nm, OBJPROP_FONTSIZE, 8);
   ObjectSetString(g_chart, nm, OBJPROP_FONT, "Consolas");
   ObjectSetString(g_chart, nm, OBJPROP_TEXT, txt);
   ObjectSetInteger(g_chart, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(g_chart, nm, OBJPROP_ZORDER, 10);
   ObjectSetInteger(g_chart, nm, OBJPROP_STATE, false);
   if(body)
      AddBody(n);
  }

void SetTxt(const string n, const string s, const color c)
  {
   ObjectSetString(g_chart, g_pfx + n, OBJPROP_TEXT, s);
   ObjectSetInteger(g_chart, g_pfx + n, OBJPROP_COLOR, c);
  }

void SetRect(const string n, const int x, const int w, const color c)
  {
   string nm = g_pfx + n;
   ObjectSetInteger(g_chart, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, nm, OBJPROP_XSIZE, MathMax(1, w));
   ObjectSetInteger(g_chart, nm, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(g_chart, nm, OBJPROP_COLOR, c);
  }

void SetVisible(const string n, const bool v)
  {
   ObjectSetInteger(g_chart, g_pfx + n, OBJPROP_TIMEFRAMES, v ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }

void BuildPanel()
  {
   int x = InpPanelX, y = InpPanelY, W = g_W;
   ArrayResize(g_body, 0);
   MkRect("bg", x, y, W, PANEL_H, pal.panel, pal.border, false);
   MkRect("hd", x, y, W, 26, pal.header, pal.header, false);
   MkLabel("title", x + 10, y + 6, 10, clrWhite, false);
   MkRect("badge", x + W - 112, y + 3, 102, 20, pal.dim, pal.dim, false);
   MkLabel("badgeT", x + W - 106, y + 6, 9, clrWhite, false);
   MkButton("btnMin", x + W - 140, y + 3, 24, 20, "-", false);

   MkLabel("clock", x + 10, y + 34, 9, pal.dim);
   MkLabel("plTxt", x + 10, y + 52, 9, pal.txt);
   MkRect("barBg", x + 10, y + 72, W - 20, 12, pal.barBg, pal.barBg);
   MkRect("barFill", x + 10, y + 72, 1, 12, pal.good, pal.good);
   MkRect("barKc", x + 10, y + 70, 2, 16, pal.accent, pal.accent);
   MkRect("barZero", x + 10, y + 70, 2, 16, pal.txt, pal.txt);
   MkRect("barCur", x + 10, y + 69, 3, 18, pal.txt, pal.txt);

   MkLabel("tbl0", x + 10, y + 94, 9, pal.dim);
   MkLabel("tbl1", x + 10, y + 110, 9, pal.txt);
   MkLabel("tbl2", x + 10, y + 126, 9, pal.txt);
   MkLabel("tbl3", x + 10, y + 142, 9, pal.txt);
   MkLabel("health", x + 10, y + 164, 9, pal.good);
   MkLabel("status", x + 10, y + 184, 9, pal.warn);
   for(int i = 0; i < 5; i++)
      MkLabel("log" + IntegerToString(i), x + 10, y + 206 + i * 14, 8, pal.dim);

   int gap = 8, bh = 24;
   int bw = (W - 20 - 2 * gap) / 3;
   int by1 = y + 286, by2 = y + 314;
   MkButton("b_pause",   x + 10,                by1, bw, bh, "");
   MkButton("b_close",   x + 10 + (bw + gap),   by1, bw, bh, "");
   MkButton("b_kunci",   x + 10 + 2 * (bw + gap), by1, bw, bh, "");
   MkButton("b_lepas",   x + 10,                by2, bw, bh, "");
   MkButton("b_dir",     x + 10 + (bw + gap),   by2, bw, bh, "");
   MkButton("b_lines",   x + 10 + 2 * (bw + gap), by2, bw, bh, "");
  }

ENUM_EA_STATE GetState()
  {
   int total = snap.mainCnt + snap.kunciCnt;
   if(g_paused && total == 0)
      return(ST_PAUSED);
   if(total == 0)
     {
      if(g_lastCloseTime > 0 && ReentryDelay() > 0 && (TimeTradeServer() - g_lastCloseTime) < ReentryDelay())
         return(ST_COOLDOWN);
      return(ST_IDLE);
     }
   if(g_isKunci)
      return(ST_LOCKED);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(snap.mainCnt < cfg.slices && snap.mainVol < g_targetLots - minLot * 0.5)
      return(ST_BUILDING);
   return(ST_ACTIVE);
  }

color PLColor(const double v)
  {
   if(v > 0.0)
      return(pal.good);
   if(v < 0.0)
      return(pal.bad);
   return(pal.txt);
  }

void UpdatePanel()
  {
   int x = InpPanelX, y = InpPanelY;
   double bal = BasketBalance();   // saldo sebelum posisi dibuka
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double total = snap.mainPL + snap.kunciPL + g_cycleRealized;
   double pct = (bal > 0.0) ? total / bal * 100.0 : 0.0;

   ENUM_EA_STATE st = GetState();
   color sc = pal.dim, bt = clrWhite;
   string sname = "";
   switch(st)
     {
      case ST_IDLE:     sname = T("SIAGA", "IDLE");        sc = pal.dim;    break;
      case ST_BUILDING: sname = T("MEMBANGUN", "BUILDING"); sc = pal.accent; break;
      case ST_ACTIVE:   sname = T("AKTIF", "ACTIVE");      sc = pal.good;   bt = clrBlack; break;
      case ST_LOCKED:   sname = T("TERKUNCI", "LOCKED");   sc = pal.warn;   bt = clrBlack; break;
      case ST_COOLDOWN: sname = T("JEDA", "COOLDOWN");     sc = pal.accent; break;
      case ST_PAUSED:   sname = T("DIJEDA", "PAUSED");     sc = pal.bad;    break;
     }
   if(st == ST_LOCKED && g_kunciIsFlip)
      sname = "FLIP";
   if(g_paused && st != ST_PAUSED)
      sname += "*";
   ObjectSetInteger(g_chart, g_pfx + "badge", OBJPROP_BGCOLOR, sc);
   ObjectSetInteger(g_chart, g_pfx + "badge", OBJPROP_COLOR, sc);
   SetTxt("badgeT", sname, bt);
   SetTxt("title", "Mesin Uang 2.30 [" + g_profileName + "]", clrWhite);
   ObjectSetString(g_chart, g_pfx + "btnMin", OBJPROP_TEXT, g_minimized ? "+" : "-");

   int basketSec = (g_basketStart > 0) ? (int)(TimeTradeServer() - g_basketStart) : 0;
   SetTxt("clock", StringFormat("%s  %s  spr %d  %s %ds%s", TimeToString(TimeTradeServer(), TIME_SECONDS), _Symbol,
          (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), T("keranjang", "basket"), basketSec,
          g_flipMode ? StringFormat("  flip %d/%d @%.0f%%", g_flipCount, InpFlipMaxCount, FlipDistancePct()) : ""), pal.dim);

   double tpRef = g_isKunci ? MathMin(cfg.profitPct, cfg.kcRecover) : cfg.profitPct;
   SetTxt("plTxt", StringFormat("P/L %+.2f%%  (TP %.2f | %s %.2f)  %s %+.2f", pct, tpRef,
          T("Rugi", "Loss"), cfg.lossPct, T("terealisasi", "realized"), g_cycleRealized), PLColor(pct));

   // bar P/L
   int bw = g_W - 20;
   double span = cfg.lossPct + tpRef;
   double v = MathMax(-cfg.lossPct, MathMin(tpRef, pct));
   int px = (int)((v + cfg.lossPct) / span * bw);
   int z  = (int)(cfg.lossPct / span * bw);
   if(px >= z)
      SetRect("barFill", x + 10 + z, px - z, pal.good);
   else
      SetRect("barFill", x + 10 + px, z - px, pal.bad);
   SetRect("barZero", x + 10 + z - 1, 2, pal.txt);
   int kcx = (int)(MathMax(0.0, cfg.lossPct - cfg.kunciPct) / span * bw);
   SetRect("barKc", x + 10 + kcx, 2, pal.accent);
   SetRect("barCur", x + 10 + px - 1, 3, PLColor(pct) == pal.txt ? pal.accent : PLColor(pct));
   if(!cfg.kcEnable || g_minimized)
      SetVisible("barKc", false);

   // tabel dua sisi
   string mainDir = (g_basketDir == NYESER_BUY) ? "BUY " : "SELL";
   string kcDir   = (g_basketDir == NYESER_BUY) ? "SELL" : "BUY ";
   double kcP = (bal > 0.0) ? snap.kunciPL / bal * 100.0 : 0.0;
   double mnP = (bal > 0.0) ? snap.mainPL / bal * 100.0 : 0.0;
   SetTxt("tbl0", StringFormat("%-16s %6s %9s %13s %9s", T("SISI", "SIDE"), T("TIKET", "TKT"), "LOT", "P/L", "P/L %"), pal.dim);
   SetTxt("tbl1", StringFormat("%-16s %6d %9.2f %+13.2f %+8.2f%%", T("UTAMA ", "MAIN ") + mainDir, snap.mainCnt, snap.mainVol,
          snap.mainPL, mnP), PLColor(snap.mainPL));
   SetTxt("tbl2", StringFormat("%-16s %6d %9.2f %+13.2f %+8.2f%%", T("KUNCI ", "LOCK ") + kcDir, snap.kunciCnt, snap.kunciVol,
          snap.kunciPL, kcP), snap.kunciCnt > 0 ? PLColor(snap.kunciPL) : pal.dim);
   SetTxt("tbl3", StringFormat("%-16s %6d %9.2f %+13.2f %+8.2f%%", "TOTAL", snap.mainCnt + snap.kunciCnt,
          snap.mainVol + snap.kunciVol, total, pct), PLColor(total));

   // kesehatan akun
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double dd = (bal > 0.0 && eq < bal) ? (bal - eq) / bal * 100.0 : 0.0;
   color hc = pal.good;
   if(cfg.killPct > 0.0 && dd >= cfg.killPct * 0.66)
      hc = pal.bad;
   else if((cfg.killPct > 0.0 && dd >= cfg.killPct * 0.33) ||
           (ml > 0.0 && cfg.minMarginLvl > 0.0 && ml < cfg.minMarginLvl))
      hc = pal.warn;
   SetTxt("health", StringFormat("Margin Lv %s  Equity %.2f  DD %.2f%%",
          ml > 0.0 ? DoubleToString(ml, 0) + "%" : "-", eq, dd), hc);

   string stxt = ">> " + g_lastAction;
   if(StringLen(stxt) > 80)
      stxt = StringSubstr(stxt, 0, 80);
   SetTxt("status", stxt, (st == ST_IDLE || st == ST_COOLDOWN || st == ST_PAUSED) ? pal.warn : pal.txt);
   for(int i = 0; i < 5; i++)
      SetTxt("log" + IntegerToString(i), g_log[i], i == 0 ? pal.txt : pal.dim);

   ObjectSetString(g_chart, g_pfx + "b_pause", OBJPROP_TEXT, g_paused ? T("LANJUT", "RESUME") : T("JEDA", "PAUSE"));
   ObjectSetString(g_chart, g_pfx + "b_close", OBJPROP_TEXT, T("TUTUP SEMUA", "CLOSE ALL"));
   ObjectSetString(g_chart, g_pfx + "b_kunci", OBJPROP_TEXT, T("KUNCI MANUAL", "MANUAL LOCK"));
   ObjectSetString(g_chart, g_pfx + "b_lepas", OBJPROP_TEXT, T("LEPAS KUNCI", "RELEASE"));
   ObjectSetString(g_chart, g_pfx + "b_dir", OBJPROP_TEXT,
                   (InpEntryMode == ENTRY_FIXED ? T("ARAH: ", "DIR: ") : T("SINYAL: ", "SIGNAL: ")) + (g_currentDir == NYESER_BUY ? "BUY" : "SELL"));
   ObjectSetString(g_chart, g_pfx + "b_lines", OBJPROP_TEXT, T("GARIS: ", "LINES: ") + (g_showLines ? "ON" : "OFF"));
   ObjectSetInteger(g_chart, g_pfx + "b_pause", OBJPROP_BGCOLOR, g_paused ? pal.bad : pal.btn);

   // minimize
   ObjectSetInteger(g_chart, g_pfx + "bg", OBJPROP_YSIZE, g_minimized ? 26 : PANEL_H);
   for(int i = 0; i < ArraySize(g_body); i++)
      SetVisible(g_body[i], !g_minimized);
   if(!g_minimized && (!cfg.kcEnable))
      SetVisible("barKc", false);
  }

void RefreshUI()
  {
   TakeSnapshot();
   UpdatePanel();
   UpdateTargetLines();
   ChartRedraw(g_chart);
  }

//+------------------------------------------------------------------+
//| Tombol panel                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, g_pfx) != 0)
      return;
   string n = StringSubstr(sparam, StringLen(g_pfx));
   ObjectSetInteger(g_chart, sparam, OBJPROP_STATE, false);
   TakeSnapshot();

   if(n == "btnMin")
      g_minimized = !g_minimized;
   else if(n == "b_pause")
     {
      g_paused = !g_paused;
      AddLog(g_paused ? T("dijeda (tanpa siklus/tiket baru)", "paused (no new cycles/slices)")
                      : T("dilanjutkan", "resumed"));
     }
   else if(n == "b_close")
     {
      if(snap.mainCnt + snap.kunciCnt > 0
         && MessageBox(T("Tutup semua posisi Mesin Uang?", "Close all Mesin Uang positions?"), "Mesin Uang",
                       MB_YESNO | MB_ICONQUESTION) == IDYES)
         CloseBasket(T("tutup manual", "manual close"));
     }
   else if(n == "b_kunci")
     {
      if(!cfg.kcEnable)
         AddLog(T("kunci nonaktif", "lock disabled"));
      else if(!g_isKunci && snap.mainVol > 0.0)
         StartKunci();
     }
   else if(n == "b_lepas")
     {
      if(g_isKunci)
         ReleaseKunciNow(T("kunci dilepas manual", "lock released manually"));
     }
   else if(n == "b_dir")
     {
      g_currentDir = (g_currentDir == NYESER_BUY) ? NYESER_SELL : NYESER_BUY;
      AddLog(T("arah siklus berikutnya: ", "next cycle direction: ") + (g_currentDir == NYESER_BUY ? "BUY" : "SELL"));
     }
   else if(n == "b_lines")
     {
      g_showLines = !g_showLines;
      g_lvSig = "";
     }
   RefreshUI();
  }
//+------------------------------------------------------------------+
