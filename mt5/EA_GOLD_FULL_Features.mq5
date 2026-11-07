//+------------------------------------------------------------------+
//|                              EA_GOLD_FULL_Features.mq5           |
//|  Trailing ✅ | Target Harian ✅ | Filter Berita ✅ | Jam Trading ✅ |
//+------------------------------------------------------------------+
#property version   "2.00"
#property strict

//==================================================
// ⚙️ SEMUA PENGATURAN DI SINI
//==================================================

input group "=== 📈 Sinyal & Momentum ==="
input int RSI_Period       = 14;
input int RSI_Jenuh_Beli   = 70;
input int RSI_Jenuh_Jual   = 30;
input int EMA_Cepat        = 10;
input int EMA_Lambat       = 21;

input group "=== 💰 Risiko & Target ==="
input double Lot_Size      = 0.01;
input int StopLoss_Pips    = 20;
input int TakeProfit_Pips  = 40;
input int Target_Profit_Harian_USD = 50;   // Tutup semua jika untung capai ini
input int Target_Loss_Harian_USD   = 30;   // Tutup semua jika rugi capai ini
input bool Reset_Target_Setiap_Hari = true;

input group "=== 🔄 Trailing Stop ==="
input bool Trailing_Aktif  = true;
input int Trailing_Start_Pips = 15;
input int Trailing_Step_Pips  = 5;

input group "=== 🕐 JAM TRADING ==="
input bool Gunakan_Jam_Trading = true;
input int Jam_Mulai_Trading  = 8;    // Mulai jam (waktu server MT5)
input int Jam_Berhenti_Trading = 20;  // Berhenti buka posisi jam ini
input int Jam_Tutup_Semua_Posisi = 23; // Tutup semua posisi jam ini

input group "=== 📰 FILTER BERITA ==="
input bool Filter_Berita_Aktif = true;
input int Jangan_Trading_X_Jam_Sebelum_Berita = 6; // Blokir X jam sebelum berita
input int Blokir_Selama_Berita_Jam = 3;             // Blokir X jam selama & setelah berita

input group "=== 🔧 Lainnya ==="
input int Magic_Number     = 88822;

//==================================================
// 📊 VARIABEL GLOBAL
//==================================================
double SL_Terkunci = 0.0;
double Harga_Buka  = 0.0;
double Profit_Hari_Ini = 0.0;
datetime Hari_Kemarin = 0;
datetime Blokir_Sampai = 0;

//==================================================
// 🔧 FUNGSI DASAR
//==================================================
double Get1Pips()
{
   int digit = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digit == 3) ? 0.01 : 0.10;
}

bool CekPosisi(ulong &ticket, ENUM_ORDER_TYPE &tipe)
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong t;
      if(!PositionGetTicket(i, t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC_NUMBER) != Magic_Number) continue;
      ticket = t;
      tipe = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

//==================================================
// 🕐 FITUR 1: JAM TRADING — Boleh Trading?
//==================================================
bool BolehBukaPosisi()
{
   if(!Gunakan_Jam_Trading) return true;
   
   int jam = TimeHour(TimeCurrent());
   if(jam < Jam_Mulai_Trading || jam >= Jam_Berhenti_Trading)
   {
      Print("🕐 Di luar jam trading (", Jam_Mulai_Trading, "-", Jam_Berhenti_Trading, ")");
      return false;
   }
   return true;
}

//==================================================
// 📰 FITUR 2: FILTER BERITA
//==================================================
bool SedangAdaBeritaPenting()
{
   if(!Filter_Berita_Aktif) return false;
   
   datetime sekarang = TimeCurrent();
   if(sekarang < Blokir_Sampai)
   {
      Print("📡 Trading diblokir karena berita sampai: ", TimeToStr(Blokir_Sampai));
      return true;
   }
   
   // Sinyal peringatan sederhana: cek pergerakan harga ekstrem
   double atr = iATR(_Symbol, _PERIOD, 14, 0);
   double atr_prev = iATR(_Symbol, _PERIOD, 14, 1);
   double atr_ma = iMA(_Symbol, _PERIOD, 14, 0, MODE_SMA, PRICE_CLOSE, 0);
   
   bool volatilitas_meningkat = (atr > atr_ma * 1.5);
   if(volatilitas_meningkat)
   {
      Blokir_Sampai = sekarang + Blokir_Selama_Berita_Jam * 3600;
      Print("⚠️ Volatilitas tinggi — kemungkinan berita. Blokir sampai: ", TimeToStr(Blokir_Sampai));
      return true;
   }
   return false;
}

//==================================================
// 💰 FITUR 3: TARGET HARIAN
//==================================================
void CekTargetHarian()
{
   datetime hari_sekarang = TimeCurrent() - TimeHour(TimeCurrent());
   if(hari_sekarang != Hari_Kemarin)
   {
      Profit_Hari_Ini = 0.0;
      Blokir_Sampai = 0;
      Hari_Kemarin = hari_sekarang;
      Print("🌅 Hari baru dimulai — Target direset");
   }
   
   // Hitung total profit hari ini
   Profit_Hari_Ini = 0.0;
   for(int i=0; i<PositionsTotal(true); i++)
   {
      ulong t;
      if(PositionGetTicket(i, t))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC_NUMBER) == Magic_Number)
         {
            Profit_Hari_Ini += PositionGetDouble(POSITION_PROFIT) +
                               PositionGetDouble(POSITION_SWAP) +
                               PositionGetDouble(POSITION_COMMISSION);
         }
      }
   }
   
   // Cek Target Untung
   if(Target_Profit_Harian_USD > 0 && Profit_Hari_Ini >= Target_Profit_Harian_USD)
   {
      Print("🎯 TARGET UNTUNG TERCAPAI: $", Profit_Hari_Ini, " / $", Target_Profit_Harian_USD);
      TutupSemuaPosisi();
   }
   
   // Cek Batas Rugi
   if(Target_Loss_Harian_USD > 0 && Profit_Hari_Ini <= -Target_Loss_Harian_USD)
   {
      Print("🛑 BATAS RUGI TERCAPAI: $", Profit_Hari_Ini, " / -$", Target_Loss_Harian_USD);
      TutupSemuaPosisi();
   }
}

//==================================================
// 🕐 FITUR 4: TUTUP POSISI OTOMATIS PADA JAM TERTENTU
//==================================================
void CekJamTutupOtomatis()
{
   int jam = TimeHour(TimeCurrent());
   if(jam == Jam_Tutup_Semua_Posisi)
   {
      static bool sudah_ditutup = false;
      if(!sudah_ditutup)
      {
         Print("🕐 Waktu tutup semua posisi: Jam ", Jam_Tutup_Semua_Posisi);
         TutupSemuaPosisi();
         sudah_ditutup = true;
      }
   }
   else
   {
      static bool sudah_ditutup = false;
      sudah_ditutup = false;
   }
}

void TutupSemuaPosisi()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket;
      if(!PositionGetTicket(i, ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC_NUMBER) != Magic_Number) continue;
      
      ENUM_ORDER_TYPE tipe = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      
      MqlTradeRequest req={0}; MqlTradeResult res={0};
      req.action = TRADE_ACTION_DEAL;
      req.symbol = _Symbol;
      req.volume = vol;
      req.type = (tipe == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.position = ticket;
      req.type_filling = ORDER_FILLING_FOK;
      
      double harga = (tipe == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      req.price = harga;
      
      OrderSend(req, res);
   }
   SL_Terkunci = 0; Harga_Buka = 0;
}

//==================================================
// 🔄 TRAILING STOP
//==================================================
void JalankanTrailingStop(ulong ticket, ENUM_ORDER_TYPE tipe)
{
   if(!Trailing_Aktif || Harga_Buka == 0) return;
   
   double pip = Get1Pips();
   double harga_sekarang = (tipe == ORDER_TYPE_BUY)
      ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double untung_pips = (tipe == ORDER_TYPE_BUY)
      ? (harga_sekarang - Harga_Buka) / pip
      : (Harga_Buka - harga_sekarang) / pip;
   
   if(untung_pips < Trailing_Start_Pips) return;
   
   double jarak_naik = untung_pips - Trailing_Start_Pips;
   int langkah = (int)MathFloor(jarak_naik / Trailing_Step_Pips);
   if(langkah <= 0) return;
   
   if(tipe == ORDER_TYPE_BUY)
   {
      double sl_baru = Harga_Buka + (Trailing_Start_Pips + langkah * Trailing_Step_Pips - StopLoss_Pips) * pip;
      if(sl_baru > SL_Terkunci + pip)
      {
         MqlTradeRequest req={0}; MqlTradeResult res={0};
         req.action=TRADE_ACTION_SLTP; req.symbol=_Symbol;
         req.sl=sl_baru; req.tp=PositionGetDouble(POSITION_TP);
         req.position=ticket;
         if(OrderSend(req,res))
         {
            SL_Terkunci = sl_baru;
            Print("🔼 Trailing naik | SL: ", SL_Terkunci);
         }
      }
   }
   else
   {
      double sl_baru = Harga_Buka - (Trailing_Start_Pips + langkah * Trailing_Step_Pips - StopLoss_Pips) * pip;
      if(sl_baru < SL_Terkunci - pip)
      {
         MqlTradeRequest req={0}; MqlTradeResult res={0};
         req.action=TRADE_ACTION_SLTP; req.symbol=_Symbol;
         req.sl=sl_baru; req.tp=PositionGetDouble(POSITION_TP);
         req.position=ticket;
         if(OrderSend(req,res))
         {
            SL_Terkunci = sl_baru;
            Print("🔽 Trailing turun | SL: ", SL_Terkunci);
         }
      }
   }
}

//==================================================
// 📊 Sinyal Momentum
//==================================================
bool SinyalBeli()
{
   if(Bars(_Symbol,_PERIOD)<50) return false;
   double r=iRSI(_Symbol,_PERIOD,RSI_Period,PRICE_CLOSE,1);
   double rp=iRSI(_Symbol,_PERIOD,RSI_Period,PRICE_CLOSE,2);
   double eF=iMA(_Symbol,_PERIOD,EMA_Cepat,0,MODE_SMA,PRICE_CLOSE,1);
   double eS=iMA(_Symbol,_PERIOD,EMA_Lambat,0,MODE_SMA,PRICE_CLOSE,1);
   double c=iClose(_Symbol,_PERIOD,1);
   return (r>rp && rp<RSI_Jenuh_Jual && c>eS && eF>eS);
}

bool SinyalJual()
{
   if(Bars(_Symbol,_PERIOD)<50) return false;
   double r=iRSI(_Symbol,_PERIOD,RSI_Period,PRICE_CLOSE,1);
   double rp=iRSI(_Symbol,_PERIOD,RSI_Period,PRICE_CLOSE,2);
   double eF=iMA(_Symbol,_PERIOD,EMA_Cepat,0,MODE_SMA,PRICE_CLOSE,1);
   double eS=iMA(_Symbol,_PERIOD,EMA_Lambat,0,MODE_SMA,PRICE_CLOSE,1);
   double c=iClose(_Symbol,_PERIOD,1);
   return (r<rp && rp>RSI_Jenuh_Beli && c<eS && eF<eS);
}

//==================================================
// 🚀 BUKA POSISI
//==================================================
bool BukaBeli()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double pip=Get1Pips();
   double sl=ask-StopLoss_Pips*pip;
   double tp=ask+TakeProfit_Pips*pip;
   
   SL_Terkunci=sl; Harga_Buka=ask;
   
   MqlTradeRequest req={0}; MqlTradeResult res={0};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lot_Size;
   req.type=ORDER_TYPE_BUY; req.price=ask; req.sl=sl; req.tp=tp;
   req.magic=Magic_Number; req.type_filling=ORDER_FILLING_FOK;
   
   bool ok=OrderSend(req,res);
   if(ok) Print("✅ BELI | Harga:",ask," SL:",sl," TP:",tp);
   return ok;
}

bool BukaJual()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double pip=Get1Pips();
   double sl=bid+StopLoss_Pips*pip;
   double tp=bid-TakeProfit_Pips*pip;
   
   SL_Terkunci=sl; Harga_Buka=bid;
   
   MqlTradeRequest req={0}; MqlTradeResult res={0};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lot_Size;
   req.type=ORDER_TYPE_SELL; req.price=bid; req.sl=sl; req.tp=tp;
   req.magic=Magic_Number; req.type_filling=ORDER_FILLING_FOK;
   
   bool ok=OrderSend(req,res);
   if(ok) Print("✅ JUAL | Harga:",bid," SL:",sl," TP:",tp);
   return ok;
}

//==================================================
// 🏠 UTAMA — DIJALANKAN SETIAP TICK
//==================================================
void OnTick()
{
   ulong ticket; ENUM_ORDER_TYPE tipe;
   bool ada_posisi = CekPosisi(ticket, tipe);
   
   // ✅ Selalu cek ini dulu
   CekTargetHarian();
   CekJamTutupOtomatis();
   
   if(ada_posisi)
   {
      JalankanTrailingStop(ticket, tipe);
   }
   else
   {
      SL_Terkunci = 0; Harga_Buka = 0;
      
      // Cek syarat sebelum buka posisi baru
      bool boleh = BolehBukaPosisi() && !SedangAdaBeritaPenting();
      
      if(boleh)
      {
         if(SinyalBeli()) BukaBeli();
         if(SinyalJual()) BukaJual();
      }
   }
}
//+------------------------------------------------------------------+
