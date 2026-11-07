//+------------------------------------------------------------------+
//|                                     EA_GOLD_FULL_Features.mq5    |
//|  Trailing | Target Harian | Filter Berita | Jam Trading          |
//|  Versi MQL5 murni (siap compile)                                 |
//+------------------------------------------------------------------+
#property copyright "EA Gold Full Features"
#property version   "2.10"
#property description "EA Gold: RSI + SMA, trailing stop, target harian, filter berita, jam trading"

#include <Trade\Trade.mqh>

//==================================================
// PENGATURAN
//==================================================
input group "=== Sinyal & Momentum ==="
input int    RSI_Period      = 14;
input int    RSI_Jenuh_Beli  = 70;
input int    RSI_Jenuh_Jual  = 30;
input int    EMA_Cepat       = 10;   // (dihitung dengan SMA, sama seperti kode asli)
input int    EMA_Lambat      = 21;

input group "=== Risiko & Target ==="
input double Lot_Size                = 0.01;
input int    StopLoss_Pips           = 20;
input int    TakeProfit_Pips         = 40;
input int    Target_Profit_Harian_USD = 50;   // Tutup semua jika untung capai ini (0 = mati)
input int    Target_Loss_Harian_USD   = 30;   // Tutup semua jika rugi capai ini (0 = mati)
input bool   Reset_Target_Setiap_Hari = true; // false = setelah tercapai, EA berhenti sampai di-restart

input group "=== Trailing Stop ==="
input bool   Trailing_Aktif       = true;
input int    Trailing_Start_Pips  = 15;
input int    Trailing_Step_Pips   = 5;

input group "=== Jam Trading (waktu server MT5) ==="
input bool   Gunakan_Jam_Trading      = true;
input int    Jam_Mulai_Trading        = 8;   // Mulai buka posisi
input int    Jam_Berhenti_Trading     = 20;  // Berhenti buka posisi
input int    Jam_Tutup_Semua_Posisi   = 23;  // Tutup semua posisi pada jam ini

input group "=== Filter Berita ==="
input bool   Filter_Berita_Aktif                  = true;
input bool   Gunakan_Kalender_Ekonomi             = true; // Kalender MT5 (USD, impact tinggi). Tidak jalan di Strategy Tester
input int    Jangan_Trading_X_Jam_Sebelum_Berita  = 6;
input int    Blokir_Selama_Berita_Jam             = 3;    // Juga dipakai sebagai lama blokir saat volatilitas melonjak
input bool   Gunakan_Filter_Volatilitas           = true; // Cadangan: blokir jika ATR melonjak
input int    ATR_Periode                          = 14;
input int    ATR_Rata_Bar                         = 20;
input double ATR_Pengali                          = 1.5;

input group "=== Lainnya ==="
input int    Magic_Number    = 88822;
input int    Slippage_Poin   = 30;

//==================================================
// VARIABEL GLOBAL
//==================================================
CTrade   trade;

int      hRSI = INVALID_HANDLE;
int      hEMAcepat = INVALID_HANDLE;
int      hEMAlambat = INVALID_HANDLE;
int      hATR = INVALID_HANDLE;

datetime g_barTerakhir     = 0;
datetime g_hariIni         = 0;
datetime g_blokirSampai    = 0;
datetime g_cekKalenderTerakhir = 0;
bool     g_kalenderBlok    = false;
bool     g_targetTercapai  = false;
bool     g_sudahTutupJam   = false;
double   g_profitHari      = 0.0;

//==================================================
// INISIALISASI
//==================================================
int OnInit()
{
   if(Trailing_Step_Pips <= 0)
   {
      Print("Trailing_Step_Pips harus lebih dari 0");
      return INIT_PARAMETERS_INCORRECT;
   }

   hRSI       = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   hEMAcepat  = iMA(_Symbol, _Period, EMA_Cepat, 0, MODE_SMA, PRICE_CLOSE);
   hEMAlambat = iMA(_Symbol, _Period, EMA_Lambat, 0, MODE_SMA, PRICE_CLOSE);
   hATR       = iATR(_Symbol, _Period, ATR_Periode);

   if(hRSI == INVALID_HANDLE || hEMAcepat == INVALID_HANDLE ||
      hEMAlambat == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Gagal membuat handle indikator. Error: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Slippage_Poin);
   trade.SetTypeFillingBySymbol(_Symbol);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE)       IndicatorRelease(hRSI);
   if(hEMAcepat != INVALID_HANDLE)  IndicatorRelease(hEMAcepat);
   if(hEMAlambat != INVALID_HANDLE) IndicatorRelease(hEMAlambat);
   if(hATR != INVALID_HANDLE)       IndicatorRelease(hATR);
}

//==================================================
// FUNGSI DASAR
//==================================================
double Get1Pips()
{
   // Emas 2 digit: 1 pip = 0.10 | 3 digit: 0.01 | 5 digit: 10 point
   return _Point * 10.0;
}

bool Buf(const int handle, const int shift, double &nilai)
{
   double b[1];
   if(CopyBuffer(handle, 0, shift, 1, b) < 1) return false;
   nilai = b[0];
   return true;
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

//==================================================
// TUTUP SEMUA POSISI
//==================================================
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
// FITUR 1: JAM TRADING
//==================================================
bool BolehBukaPosisi()
{
   if(!Gunakan_Jam_Trading) return true;

   int jam = JamServer();
   if(Jam_Mulai_Trading < Jam_Berhenti_Trading)
      return (jam >= Jam_Mulai_Trading && jam < Jam_Berhenti_Trading);

   // Rentang melewati tengah malam (misal 22 -> 6)
   return (jam >= Jam_Mulai_Trading || jam < Jam_Berhenti_Trading);
}

//==================================================
// FITUR 2: FILTER BERITA
//==================================================
bool KalenderAdaBeritaPenting(const datetime sekarang)
{
   // Cek maksimal 1x per menit agar tidak berat
   if(sekarang - g_cekKalenderTerakhir < 60) return g_kalenderBlok;
   g_cekKalenderTerakhir = sekarang;
   g_kalenderBlok = false;

   MqlCalendarValue nilai[];
   datetime dari = sekarang - Blokir_Selama_Berita_Jam * 3600;
   datetime ke   = sekarang + Jangan_Trading_X_Jam_Sebelum_Berita * 3600;

   if(!CalendarValueHistory(nilai, dari, ke, NULL, "USD")) return false;

   for(int i = 0; i < ArraySize(nilai); i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(nilai[i].event_id, ev)) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
      {
         g_kalenderBlok = true;
         break;
      }
   }
   return g_kalenderBlok;
}

bool VolatilitasMelonjak()
{
   double atrSekarang;
   if(!Buf(hATR, 1, atrSekarang)) return false;

   double arr[];
   if(CopyBuffer(hATR, 0, 2, ATR_Rata_Bar, arr) < ATR_Rata_Bar) return false;

   double total = 0;
   for(int i = 0; i < ATR_Rata_Bar; i++) total += arr[i];
   double rata = total / ATR_Rata_Bar;

   return (rata > 0 && atrSekarang > rata * ATR_Pengali);
}

bool SedangAdaBeritaPenting()
{
   if(!Filter_Berita_Aktif) return false;

   datetime sekarang = TimeCurrent();
   if(sekarang < g_blokirSampai) return true;

   if(Gunakan_Kalender_Ekonomi && KalenderAdaBeritaPenting(sekarang))
      return true;

   if(Gunakan_Filter_Volatilitas && VolatilitasMelonjak())
   {
      g_blokirSampai = sekarang + Blokir_Selama_Berita_Jam * 3600;
      Print("Volatilitas tinggi (kemungkinan berita). Blokir sampai: ",
            TimeToString(g_blokirSampai, TIME_DATE | TIME_MINUTES));
      return true;
   }
   return false;
}

//==================================================
// FITUR 3: TARGET HARIAN
//==================================================
double HitungProfitHariIni(const datetime awalHari)
{
   double total = 0.0;

   // 1) Posisi yang sudah ditutup (dan komisi masuk posisi yang masih terbuka)
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

   // 2) Floating profit posisi yang masih terbuka
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

   if(awalHari != g_hariIni)
   {
      g_hariIni      = awalHari;
      g_blokirSampai = 0;
      if(Reset_Target_Setiap_Hari) g_targetTercapai = false;
      Print("Hari baru dimulai - target direset");
   }

   if(g_targetTercapai) return;

   g_profitHari = HitungProfitHariIni(awalHari);

   if(Target_Profit_Harian_USD > 0 && g_profitHari >= Target_Profit_Harian_USD)
   {
      Print("TARGET UNTUNG TERCAPAI: $", DoubleToString(g_profitHari, 2),
            " / $", Target_Profit_Harian_USD);
      g_targetTercapai = true;
      TutupSemuaPosisi();
      return;
   }

   if(Target_Loss_Harian_USD > 0 && g_profitHari <= -Target_Loss_Harian_USD)
   {
      Print("BATAS RUGI TERCAPAI: $", DoubleToString(g_profitHari, 2),
            " / -$", Target_Loss_Harian_USD);
      g_targetTercapai = true;
      TutupSemuaPosisi();
   }
}

//==================================================
// FITUR 4: TUTUP POSISI OTOMATIS PADA JAM TERTENTU
//==================================================
void CekJamTutupOtomatis()
{
   if(!Gunakan_Jam_Trading) return;

   if(JamServer() == Jam_Tutup_Semua_Posisi)
   {
      if(!g_sudahTutupJam)
      {
         Print("Waktu tutup semua posisi: jam ", Jam_Tutup_Semua_Posisi);
         TutupSemuaPosisi();
         g_sudahTutupJam = true;
      }
   }
   else
   {
      g_sudahTutupJam = false;
   }
}

//==================================================
// TRAILING STOP
//==================================================
void JalankanTrailingStop(const ulong ticket)
{
   if(!Trailing_Aktif) return;
   if(!PositionSelectByTicket(ticket)) return;

   ENUM_POSITION_TYPE tipe = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double hargaBuka = PositionGetDouble(POSITION_PRICE_OPEN);
   double slSekarang = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   double pip = Get1Pips();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double untungPips = (tipe == POSITION_TYPE_BUY) ? (bid - hargaBuka) / pip
                                                   : (hargaBuka - ask) / pip;
   if(untungPips < Trailing_Start_Pips) return;

   int langkah = (int)MathFloor((untungPips - Trailing_Start_Pips) / Trailing_Step_Pips);
   if(langkah <= 0) return;

   double geser = (Trailing_Start_Pips + langkah * Trailing_Step_Pips - StopLoss_Pips) * pip;
   double minJarak = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   if(tipe == POSITION_TYPE_BUY)
   {
      double slBaru = NormalizeDouble(hargaBuka + geser, _Digits);
      if(slBaru > slSekarang + pip && slBaru < bid - minJarak)
      {
         if(trade.PositionModify(ticket, slBaru, tp))
            Print("Trailing naik | SL: ", DoubleToString(slBaru, _Digits));
      }
   }
   else
   {
      double slBaru = NormalizeDouble(hargaBuka - geser, _Digits);
      if((slSekarang == 0.0 || slBaru < slSekarang - pip) && slBaru > ask + minJarak)
      {
         if(trade.PositionModify(ticket, slBaru, tp))
            Print("Trailing turun | SL: ", DoubleToString(slBaru, _Digits));
      }
   }
}

//==================================================
// SINYAL MOMENTUM
//==================================================
bool AmbilDataSinyal(double &r, double &rp, double &eF, double &eS, double &c)
{
   if(Bars(_Symbol, _Period) < 50) return false;
   if(!Buf(hRSI, 1, r))        return false;
   if(!Buf(hRSI, 2, rp))       return false;
   if(!Buf(hEMAcepat, 1, eF))  return false;
   if(!Buf(hEMAlambat, 1, eS)) return false;
   c = iClose(_Symbol, _Period, 1);
   return (c > 0);
}

bool SinyalBeli()
{
   double r, rp, eF, eS, c;
   if(!AmbilDataSinyal(r, rp, eF, eS, c)) return false;
   return (r > rp && rp < RSI_Jenuh_Jual && c > eS && eF > eS);
}

bool SinyalJual()
{
   double r, rp, eF, eS, c;
   if(!AmbilDataSinyal(r, rp, eF, eS, c)) return false;
   return (r < rp && rp > RSI_Jenuh_Beli && c < eS && eF < eS);
}

//==================================================
// BUKA POSISI
//==================================================
bool BukaPosisi(const ENUM_ORDER_TYPE tipe)
{
   double pip = Get1Pips();
   double lot = NormalisasiLot(Lot_Size);
   double harga, sl, tp;
   bool ok;

   if(tipe == ORDER_TYPE_BUY)
   {
      harga = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(harga - StopLoss_Pips * pip, _Digits);
      tp = NormalizeDouble(harga + TakeProfit_Pips * pip, _Digits);
      ok = trade.Buy(lot, _Symbol, harga, sl, tp, "EA Gold");
   }
   else
   {
      harga = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(harga + StopLoss_Pips * pip, _Digits);
      tp = NormalizeDouble(harga - TakeProfit_Pips * pip, _Digits);
      ok = trade.Sell(lot, _Symbol, harga, sl, tp, "EA Gold");
   }

   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
   {
      Print((tipe == ORDER_TYPE_BUY ? "BELI" : "JUAL"), " | Harga: ", harga,
            " SL: ", sl, " TP: ", tp);
      return true;
   }

   Print("Order gagal | retcode: ", rc, " | ", trade.ResultRetcodeDescription());
   return false;
}

//==================================================
// UTAMA - DIJALANKAN SETIAP TICK
//==================================================
void OnTick()
{
   // Selalu dicek di setiap tick
   CekTargetHarian();
   CekJamTutupOtomatis();

   ulong ticket;
   if(CekPosisi(ticket))
   {
      JalankanTrailingStop(ticket);
      return;
   }

   // Sinyal hanya dievaluasi sekali per bar baru
   datetime barSekarang = iTime(_Symbol, _Period, 0);
   if(barSekarang == g_barTerakhir) return;
   g_barTerakhir = barSekarang;

   if(g_targetTercapai)              return;
   if(!BolehBukaPosisi())            return;
   if(SedangAdaBeritaPenting())      return;

   if(SinyalBeli())      BukaPosisi(ORDER_TYPE_BUY);
   else if(SinyalJual()) BukaPosisi(ORDER_TYPE_SELL);
}
//+------------------------------------------------------------------+
