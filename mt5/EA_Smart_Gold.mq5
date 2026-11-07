//+------------------------------------------------------------------+
//|                                              EA_Smart_Gold.mq5   |
//|                  Smart Money Concepts - SL Lengkap & Aman        |
//|                  Versi MQL5 murni (siap compile)                 |
//+------------------------------------------------------------------+
#property copyright "EA Smart Gold"
#property version   "1.20"
#property description "EA Gold: FVG + Order Block + perubahan struktur, SL di luar zona, target harian"

#include <Trade\Trade.mqh>

//==================================================
// PENGATURAN INPUT
//==================================================
input group "=== STRUKTUR PASAR ==="
input int    Struktur_Lookback   = 3;
input double FVG_Min_Rasio       = 0.3;   // Ukuran gap minimum = rasio x range candle tengah
input int    Zona_Maks_Umur_Bar  = 30;    // Zona FVG/OB dibuang jika lebih tua dari ini

input group "=== STOP LOSS & TAKE PROFIT ==="
input int    StopLoss_Pips       = 30;    // Jarak SL minimum dari harga buka
input double RR_Ratio            = 1.5;   // Rasio Risk:Reward
input bool   SL_Di_Luar_Zona     = true;  // SL diletakkan di luar zona FVG/OB (jika lebih jauh)

input group "=== MANAJEMEN RISIKO ==="
input double Lot_Size                = 0.01;
input double Target_Profit_Harian_USD = 50;  // 0 = mati
input double Max_Loss_Harian_USD      = 30;  // 0 = mati

input group "=== JAM TRADING (waktu server MT5) ==="
input bool   Gunakan_Jam         = true;
input int    Jam_Mulai           = 8;
input int    Jam_Berhenti        = 20;

input group "=== LAINNYA ==="
input int    Magic_Number        = 99911;
input int    Slippage_Poin       = 30;

//==================================================
// STRUKTUR DATA
//==================================================
struct FVG_Zone
{
   bool     aktif;
   datetime mulai;
   double   atas;
   double   bawah;
   double   tengah;
   bool     arah_beli;
};

struct OrderBlock
{
   bool     aktif;
   double   harga;
   bool     arah_beli;
   datetime waktu;
};

//==================================================
// VARIABEL GLOBAL
//==================================================
CTrade     trade;

FVG_Zone   g_FVG;
OrderBlock g_OB_Beli, g_OB_Jual;

double     g_Profit_Harian   = 0.0;
datetime   g_Hari_Ini        = 0;
bool       g_TargetTercapai  = false;
datetime   g_BarTerakhir     = 0;   // bar terakhir yang dipakai untuk deteksi zona
datetime   g_BarCobaOrder    = 0;   // bar terakhir saat order dicoba (cegah spam)

//==================================================
// INISIALISASI
//==================================================
void ResetZona()
{
   g_FVG.aktif = false;
   g_FVG.mulai = 0;
   g_FVG.atas = 0; g_FVG.bawah = 0; g_FVG.tengah = 0;
   g_FVG.arah_beli = true;

   g_OB_Beli.aktif = false; g_OB_Beli.harga = 0; g_OB_Beli.arah_beli = true;  g_OB_Beli.waktu = 0;
   g_OB_Jual.aktif = false; g_OB_Jual.harga = 0; g_OB_Jual.arah_beli = false; g_OB_Jual.waktu = 0;
}

int OnInit()
{
   ResetZona();

   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Slippage_Poin);
   trade.SetTypeFillingBySymbol(_Symbol);

   return INIT_SUCCEEDED;
}

//==================================================
// FUNGSI DASAR
//==================================================
double GetPipSize()
{
   // Emas 2 digit: 0.10 | 3 digit: 0.01 | 5 digit: 0.0001 | 4 digit: 0.0001
   int digit = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digit == 4) return _Point;
   return _Point * 10.0;
}

int JamServer()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour;
}

double NormalisasiLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot > 0) lot = MathRound(lot / stepLot) * stepLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

bool CekPosisi(ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      ticket = t;
      return true;
   }
   return false;
}

void TutupSemuaPosisi()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;

      if(!trade.PositionClose(t))
         Print("Gagal menutup posisi #", t, " | retcode: ", trade.ResultRetcode(),
               " | ", trade.ResultRetcodeDescription());
   }
}

//==================================================
// DETEKSI FVG & ORDER BLOCK (dipanggil sekali per bar baru)
//==================================================
void DeteksiFVG()
{
   if(Bars(_Symbol, _Period) < 5) return;

   double h3 = iHigh(_Symbol, _Period, 3), l3 = iLow(_Symbol, _Period, 3);
   double h2 = iHigh(_Symbol, _Period, 2), l2 = iLow(_Symbol, _Period, 2);
   double h1 = iHigh(_Symbol, _Period, 1), l1 = iLow(_Symbol, _Period, 1);

   double range_tengah = h2 - l2;

   // FVG naik: low candle 1 di atas high candle 3
   if(l1 > h3)
   {
      double gap = l1 - h3;
      if(range_tengah <= 0 || gap >= FVG_Min_Rasio * range_tengah)
      {
         g_FVG.aktif     = true;
         g_FVG.arah_beli = true;
         g_FVG.atas      = l1;
         g_FVG.bawah     = h3;
         g_FVG.tengah    = (l1 + h3) / 2.0;
         g_FVG.mulai     = iTime(_Symbol, _Period, 1);
      }
   }
   // FVG turun: high candle 1 di bawah low candle 3
   else if(l3 > h1)
   {
      double gap = l3 - h1;
      if(range_tengah <= 0 || gap >= FVG_Min_Rasio * range_tengah)
      {
         g_FVG.aktif     = true;
         g_FVG.arah_beli = false;
         g_FVG.atas      = l3;
         g_FVG.bawah     = h1;
         g_FVG.tengah    = (l3 + h1) / 2.0;
         g_FVG.mulai     = iTime(_Symbol, _Period, 1);
      }
   }
}

void DeteksiOrderBlock()
{
   if(Bars(_Symbol, _Period) < 5) return;

   bool ob_beli = iClose(_Symbol, _Period, 3) < iOpen(_Symbol, _Period, 3)
               && iClose(_Symbol, _Period, 2) < iOpen(_Symbol, _Period, 2)
               && iLow(_Symbol, _Period, 1)   > iLow(_Symbol, _Period, 2)
               && iClose(_Symbol, _Period, 1) > iHigh(_Symbol, _Period, 2);
   if(ob_beli)
   {
      g_OB_Beli.aktif     = true;
      g_OB_Beli.harga     = iLow(_Symbol, _Period, 2);
      g_OB_Beli.arah_beli = true;
      g_OB_Beli.waktu     = iTime(_Symbol, _Period, 2);
   }

   bool ob_jual = iClose(_Symbol, _Period, 3) > iOpen(_Symbol, _Period, 3)
               && iClose(_Symbol, _Period, 2) > iOpen(_Symbol, _Period, 2)
               && iHigh(_Symbol, _Period, 1)  < iHigh(_Symbol, _Period, 2)
               && iClose(_Symbol, _Period, 1) < iLow(_Symbol, _Period, 2);
   if(ob_jual)
   {
      g_OB_Jual.aktif     = true;
      g_OB_Jual.harga     = iHigh(_Symbol, _Period, 2);
      g_OB_Jual.arah_beli = false;
      g_OB_Jual.waktu     = iTime(_Symbol, _Period, 2);
   }
}

// Buang zona yang sudah terlalu tua
void BersihkanZonaLama()
{
   if(Zona_Maks_Umur_Bar <= 0) return;

   if(g_FVG.aktif)
   {
      int umur = iBarShift(_Symbol, _Period, g_FVG.mulai, false);
      if(umur < 0 || umur > Zona_Maks_Umur_Bar) g_FVG.aktif = false;
   }
   if(g_OB_Beli.aktif)
   {
      int umur = iBarShift(_Symbol, _Period, g_OB_Beli.waktu, false);
      if(umur < 0 || umur > Zona_Maks_Umur_Bar) g_OB_Beli.aktif = false;
   }
   if(g_OB_Jual.aktif)
   {
      int umur = iBarShift(_Symbol, _Period, g_OB_Jual.waktu, false);
      if(umur < 0 || umur > Zona_Maks_Umur_Bar) g_OB_Jual.aktif = false;
   }
}

//==================================================
// STRUKTUR PASAR
//==================================================
bool StrukturBerubah_Naik()
{
   if(Bars(_Symbol, _Period) <= Struktur_Lookback + 1) return false;

   double tertinggi_sekarang = iHigh(_Symbol, _Period, 1);
   double tertinggi_sebelum  = 0;
   for(int i = 2; i <= Struktur_Lookback; i++)
      tertinggi_sebelum = MathMax(tertinggi_sebelum, iHigh(_Symbol, _Period, i));

   return (tertinggi_sekarang > tertinggi_sebelum);
}

bool StrukturBerubah_Turun()
{
   if(Bars(_Symbol, _Period) <= Struktur_Lookback + 1) return false;

   double terendah_sekarang = iLow(_Symbol, _Period, 1);
   double terendah_sebelum  = DBL_MAX;
   for(int i = 2; i <= Struktur_Lookback; i++)
      terendah_sebelum = MathMin(terendah_sebelum, iLow(_Symbol, _Period, i));

   return (terendah_sekarang < terendah_sebelum);
}

//==================================================
// HITUNG STOP LOSS
//==================================================
double HitungSL_Beli(const double harga_buka)
{
   double pip      = GetPipSize();
   double SL_jarak = StopLoss_Pips * pip;
   double sl       = harga_buka - SL_jarak;

   if(SL_Di_Luar_Zona)
   {
      if(g_FVG.aktif && g_FVG.arah_beli)
         sl = MathMin(sl, g_FVG.bawah - pip * 5);        // 5 pips di bawah zona FVG
      if(g_OB_Beli.aktif && g_OB_Beli.arah_beli)
         sl = MathMin(sl, g_OB_Beli.harga - pip * 5);    // 5 pips di bawah OB
   }
   return sl;
}

double HitungSL_Jual(const double harga_buka)
{
   double pip      = GetPipSize();
   double SL_jarak = StopLoss_Pips * pip;
   double sl       = harga_buka + SL_jarak;

   if(SL_Di_Luar_Zona)
   {
      if(g_FVG.aktif && !g_FVG.arah_beli)
         sl = MathMax(sl, g_FVG.atas + pip * 5);         // 5 pips di atas zona FVG
      if(g_OB_Jual.aktif && !g_OB_Jual.arah_beli)
         sl = MathMax(sl, g_OB_Jual.harga + pip * 5);    // 5 pips di atas OB
   }
   return sl;
}

//==================================================
// JAM TRADING & TARGET HARIAN
//==================================================
bool BolehTradingJam()
{
   if(!Gunakan_Jam) return true;

   int jam = JamServer();
   if(Jam_Mulai < Jam_Berhenti)
      return (jam >= Jam_Mulai && jam < Jam_Berhenti);

   return (jam >= Jam_Mulai || jam < Jam_Berhenti);   // melewati tengah malam
}

double HitungProfitHariIni(const datetime awalHari)
{
   double total = 0.0;

   // Posisi yang sudah ditutup hari ini (termasuk komisi entry posisi yang masih terbuka)
   if(HistorySelect(awalHari, TimeCurrent() + 60))
   {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != Magic_Number) continue;

         long tipe = HistoryDealGetInteger(deal, DEAL_TYPE);
         if(tipe != DEAL_TYPE_BUY && tipe != DEAL_TYPE_SELL) continue;

         total += HistoryDealGetDouble(deal, DEAL_PROFIT)
                + HistoryDealGetDouble(deal, DEAL_SWAP)
                + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                + HistoryDealGetDouble(deal, DEAL_FEE);
      }
   }

   // Floating profit posisi yang masih terbuka
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

void CekTargetHarian()
{
   datetime awalHari = iTime(_Symbol, PERIOD_D1, 0);
   if(awalHari == 0) return;

   if(awalHari != g_Hari_Ini)
   {
      g_Hari_Ini        = awalHari;
      g_Profit_Harian   = 0;
      g_TargetTercapai  = false;
      ResetZona();
      Print("Hari baru dimulai - target direset");
   }

   if(g_TargetTercapai) return;

   g_Profit_Harian = HitungProfitHariIni(awalHari);

   if(Target_Profit_Harian_USD > 0 && g_Profit_Harian >= Target_Profit_Harian_USD)
   {
      Print("TARGET UNTUNG TERCAPAI: $", DoubleToString(g_Profit_Harian, 2));
      g_TargetTercapai = true;
      TutupSemuaPosisi();
      return;
   }
   if(Max_Loss_Harian_USD > 0 && g_Profit_Harian <= -Max_Loss_Harian_USD)
   {
      Print("BATAS RUGI TERCAPAI: $", DoubleToString(g_Profit_Harian, 2));
      g_TargetTercapai = true;
      TutupSemuaPosisi();
   }
}

//==================================================
// BUKA POSISI (SL & TP LANGSUNG DIPASANG)
//==================================================
bool BukaBeli()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minJarak = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   double sl = HitungSL_Beli(ask);
   if(bid - sl < minJarak) sl = bid - minJarak - _Point;       // patuhi stop level broker

   double risk = ask - sl;
   if(risk <= 0) return false;

   double tp = ask + risk * RR_Ratio;
   if(tp - bid < minJarak) tp = bid + minJarak + _Point;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool ok = trade.Buy(NormalisasiLot(Lot_Size), _Symbol, ask, sl, tp, "Smart Gold");
   uint rc = trade.ResultRetcode();

   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
   {
      Print("BELI | Harga: ", ask, " | SL: ", sl, " | TP: ", tp);
      return true;
   }
   Print("GAGAL BELI | retcode: ", rc, " | ", trade.ResultRetcodeDescription());
   return false;
}

bool BukaJual()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minJarak = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   double sl = HitungSL_Jual(bid);
   if(sl - ask < minJarak) sl = ask + minJarak + _Point;       // patuhi stop level broker

   double risk = sl - bid;
   if(risk <= 0) return false;

   double tp = bid - risk * RR_Ratio;
   if(ask - tp < minJarak) tp = ask - minJarak - _Point;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool ok = trade.Sell(NormalisasiLot(Lot_Size), _Symbol, bid, sl, tp, "Smart Gold");
   uint rc = trade.ResultRetcode();

   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
   {
      Print("JUAL | Harga: ", bid, " | SL: ", sl, " | TP: ", tp);
      return true;
   }
   Print("GAGAL JUAL | retcode: ", rc, " | ", trade.ResultRetcodeDescription());
   return false;
}

//==================================================
// UTAMA
//==================================================
void OnTick()
{
   CekTargetHarian();

   // Sudah ada posisi: SL/TP sudah terpasang di server, tidak perlu apa-apa lagi
   ulong ticket;
   if(CekPosisi(ticket)) return;

   // Deteksi zona sekali per bar baru
   datetime barSekarang = iTime(_Symbol, _Period, 0);
   if(barSekarang != g_BarTerakhir)
   {
      g_BarTerakhir = barSekarang;
      DeteksiFVG();
      DeteksiOrderBlock();
      BersihkanZonaLama();
   }

   if(g_TargetTercapai)  return;
   if(!BolehTradingJam()) return;

   // Maksimal 1x percobaan order per bar (hindari spam jika order ditolak)
   if(g_BarCobaOrder == barSekarang) return;

   double harga = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip   = GetPipSize();

   // BELI
   if(StrukturBerubah_Naik())
   {
      bool di_FVG = g_FVG.aktif && g_FVG.arah_beli && harga >= g_FVG.bawah && harga <= g_FVG.atas;
      bool di_OB  = g_OB_Beli.aktif && MathAbs(harga - g_OB_Beli.harga) < pip * 10;
      if(di_FVG || di_OB)
      {
         g_BarCobaOrder = barSekarang;
         if(BukaBeli()) { g_FVG.aktif = false; g_OB_Beli.aktif = false; }
         return;
      }
   }

   // JUAL
   if(StrukturBerubah_Turun())
   {
      bool di_FVG = g_FVG.aktif && !g_FVG.arah_beli && harga >= g_FVG.bawah && harga <= g_FVG.atas;
      bool di_OB  = g_OB_Jual.aktif && MathAbs(harga - g_OB_Jual.harga) < pip * 10;
      if(di_FVG || di_OB)
      {
         g_BarCobaOrder = barSekarang;
         if(BukaJual()) { g_FVG.aktif = false; g_OB_Jual.aktif = false; }
         return;
      }
   }
}
//+------------------------------------------------------------------+
