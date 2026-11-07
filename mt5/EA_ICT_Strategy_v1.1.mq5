//+------------------------------------------------------------------+
//|                                   EA_ICT_Strategy_v1.1.mq5       |
//|                     Smart Money Concepts — SL Lengkap & Aman    |
//+------------------------------------------------------------------+
#property version   "1.10"
#property strict

//==================================================
// ⚙️ PENGATURAN INPUT — STOP LOSS DAPAT DIATUR
//==================================================
input group "=== 📊 STRUKTUR PASAR ==="
input int Struktur_Lookback = 3;
input double FVG_Min_Rasio = 0.3;

input group "=== 🛡️ STOP LOSS & TAKE PROFIT ==="
input int StopLoss_Pips = 30;                  // ✅ Jarak SL dari harga buka
input double RR_Ratio = 1.5;                    // Rasio Risk:Reward
input bool SL_Di_Luar_Zona = true;              // ✅ SL ditempatkan di luar zona FVG/OB

input group "=== 💰 MANAJEMEN RISIKO ==="
input double Lot_Size = 0.01;
input double Target_Profit_Harian_USD = 50;
input double Max_Loss_Harian_USD = 30;

input group "=== 📅 JAM TRADING ==="
input bool Gunakan_Jam = true;
input int Jam_Mulai = 8;
input int Jam_Berhenti = 20;

input group "=== 🔧 LAINNYA ==="
input int Magic_Number = 99911;

//==================================================
// 📊 STRUKTUR DATA
//==================================================
struct FVG_Zone
{
   bool aktif;
   datetime mulai;
   double atas;
   double bawah;
   double tengah;
   bool arah_beli;
};

struct OrderBlock
{
   bool aktif;
   double harga;
   bool arah_beli;
   datetime waktu;
};

//==================================================
// 📈 VARIABEL GLOBAL
//==================================================
FVG_Zone g_FVG;
OrderBlock g_OB_Beli, g_OB_Jual;
double g_Profit_Harian = 0;
datetime g_Hari_Lalu = 0;
double g_SL_Aktif = 0;  // ✅ Simpan SL aktif
double g_TP_Aktif = 0;  // ✅ Simpan TP aktif

//==================================================
// 🔧 FUNGSI DASAR
//==================================================
double GetPipSize()
{
   int digit = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digit == 3) ? 0.01 : (digit == 5) ? 0.0001 : 0.10;
}

bool CekPosisi(ulong &ticket, ENUM_ORDER_TYPE &tipe)
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong t = INVALID_ORDER_TICKET;
      if(!PositionGetTicket(i, t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC_NUMBER) != Magic_Number) continue;
      ticket = t;
      tipe = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

void TutupSemuaPosisi()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong t;
      if(!PositionGetTicket(i, t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC_NUMBER) != Magic_Number) continue;
      
      ENUM_ORDER_TYPE tipe = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      
      MqlTradeRequest req={0}; MqlTradeResult res={0};
      req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=vol;
      req.type=(tipe==ORDER_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      req.position=ticket;
      req.type_filling=ORDER_FILLING_FOK;
      req.price=(tipe==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      OrderSend(req,res);
   }
   g_SL_Aktif = 0;
   g_TP_Aktif = 0;
}

//==================================================
// 📊 DETEKSI FVG & ORDER BLOCK
//==================================================
void DeteksiFVG()
{
   if(Bars(_Symbol,_PERIOD)<5) return;
   double h3=iHigh(_Symbol,_PERIOD,3), l3=iLow(_Symbol,_PERIOD,3);
   double h2=iHigh(_Symbol,_PERIOD,2), l2=iLow(_Symbol,_PERIOD,2);
   double h1=iHigh(_Symbol,_PERIOD,1), l1=iLow(_Symbol,_PERIOD,1);
   
   if(h3<l1 && l2>h3)
   {
      g_FVG.aktif=true; g_FVG.arah_beli=true;
      g_FVG.atas=l1; g_FVG.bawah=h3; g_FVG.tengah=(l1+h3)/2;
      g_FVG.mulai=TimeCurrent();
   }
   if(l3>h1 && h2<l3)
   {
      g_FVG.aktif=true; g_FVG.arah_beli=false;
      g_FVG.atas=l3; g_FVG.bawah=h1; g_FVG.tengah=(l3+h1)/2;
      g_FVG.mulai=TimeCurrent();
   }
}

void DeteksiOrderBlock()
{
   if(Bars(_Symbol,_PERIOD)<5) return;
   bool ob_beli = iClose(_Symbol,_PERIOD,3)<iOpen(_Symbol,_PERIOD,3)
               && iClose(_Symbol,_PERIOD,2)<iOpen(_Symbol,_PERIOD,2)
               && iLow(_Symbol,_PERIOD,1)>iLow(_Symbol,_PERIOD,2)
               && iClose(_Symbol,_PERIOD,1)>iHigh(_Symbol,_PERIOD,2);
   if(ob_beli) { g_OB_Beli.aktif=true; g_OB_Beli.harga=iLow(_Symbol,_PERIOD,2); g_OB_Beli.arah_beli=true; }
   
   bool ob_jual = iClose(_Symbol,_PERIOD,3)>iOpen(_Symbol,_PERIOD,3)
                && iClose(_Symbol,_PERIOD,2)>iOpen(_Symbol,_PERIOD,2)
                && iHigh(_Symbol,_PERIOD,1)<iHigh(_Symbol,_PERIOD,2)
                && iClose(_Symbol,_PERIOD,1)<iLow(_Symbol,_PERIOD,2);
   if(ob_jual) { g_OB_Jual.aktif=true; g_OB_Jual.harga=iHigh(_Symbol,_PERIOD,2); g_OB_Jual.arah_beli=false; }
}

//==================================================
// 🔄 STRUKTUR PASAR
//==================================================
bool StrukturBerubah_Naik()
{
   if(Bars(_Symbol,_PERIOD)<=Struktur_Lookback+1) return false;
   double tertinggi_sekarang=iHigh(_Symbol,_PERIOD,1), tertinggi_sebelum=0;
   for(int i=2; i<=Struktur_Lookback; i++) tertinggi_sebelum=MathMax(tertinggi_sebelum,iHigh(_Symbol,_PERIOD,i));
   return (tertinggi_sekarang>tertinggi_sebelum);
}

bool StrukturBerubah_Turun()
{
   if(Bars(_Symbol,_PERIOD)<=Struktur_Lookback+1) return false;
   double terendah_sekarang=iLow(_Symbol,_PERIOD,1), terendah_sebelum=999999;
   for(int i=2; i<=Struktur_Lookback; i++) terendah_sebelum=MathMin(terendah_sebelum,iLow(_Symbol,_PERIOD,i));
   return (terendah_sekarang<terendah_sebelum);
}

//==================================================
// 🛡️ HITUNG STOP LOSS — INTI FITUR INI
//==================================================
double HitungSL_Beli(double harga_buka)
{
   double pip = GetPipSize();
   double SL_jarak = StopLoss_Pips * pip;
   
   // ✅ Jika SL di luar zona — letakkan di bawah zona FVG/OB
   if(SL_Di_Luar_Zona && g_FVG.aktif && g_FVG.arah_beli)
   {
      double SL_di_bawah_FVG = g_FVG.bawah - (pip * 5); // 5 pips di bawah zona
      return MathMin(harga_buka - SL_jarak, SL_di_bawah_FVG);
   }
   if(SL_Di_Luar_Zona && g_OB_Beli.aktif && g_OB_Beli.arah_beli)
   {
      double SL_di_bawah_OB = g_OB_Beli.harga - (pip * 5); // 5 pips di bawah OB
      return MathMin(harga_buka - SL_jarak, SL_di_bawah_OB);
   }
   
   // ✅ SL standar berdasarkan jarak pips
   return harga_buka - SL_jarak;
}

double HitungSL_Jual(double harga_buka)
{
   double pip = GetPipSize();
   double SL_jarak = StopLoss_Pips * pip;
   
   // ✅ Jika SL di luar zona — letakkan di atas zona FVG/OB
   if(SL_Di_Luar_Zona && g_FVG.aktif && !g_FVG.arah_beli)
   {
      double SL_di_atas_FVG = g_FVG.atas + (pip * 5); // 5 pips di atas zona
      return MathMax(harga_buka + SL_jarak, SL_di_atas_FVG);
   }
   if(SL_Di_Luar_Zona && g_OB_Jual.aktif && !g_OB_Jual.arah_beli)
   {
      double SL_di_atas_OB = g_OB_Jual.harga + (pip * 5); // 5 pips di atas OB
      return MathMax(harga_buka + SL_jarak, SL_di_atas_OB);
   }
   
   // ✅ SL standar berdasarkan jarak pips
   return harga_buka + SL_jarak;
}

//==================================================
// 🎯 TARGET HARIAN & JAM TRADING
//==================================================
bool BolehTradingJam()
{
   if(!Gunakan_Jam) return true;
   int jam = TimeHour(TimeCurrent());
   return (jam >= Jam_Mulai && jam < Jam_Berhenti);
}

void CekTargetHarian()
{
   datetime hari_ini = TimeCurrent() - TimeHour(TimeCurrent());
   if(hari_ini != g_Hari_Lalu)
   {
      g_Profit_Harian = 0;
      g_Hari_Lalu = hari_ini;
      g_FVG.aktif = false;
      g_OB_Beli.aktif = false;
      g_OB_Jual.aktif = false;
      g_SL_Aktif = 0;
      g_TP_Aktif = 0;
   }
   
   g_Profit_Harian = 0;
   for(int i=0; i<PositionsTotal(true); i++)
   {
      ulong t;
      if(PositionGetTicket(i,t))
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC_NUMBER)==Magic_Number)
            g_Profit_Harian += PositionGetDouble(POSITION_PROFIT);
   }
   
   if(Target_Profit_Harian_USD>0 && g_Profit_Harian>=Target_Profit_Harian_USD)
   {
      Print("🎯 TARGET UNTUNG TERCAPAI: $", g_Profit_Harian);
      TutupSemuaPosisi();
   }
   if(Max_Loss_Harian_USD>0 && g_Profit_Harian<=-Max_Loss_Harian_USD)
   {
      Print("🛑 BATAS RUGI TERCAPAI: $", g_Profit_Harian);
      TutupSemuaPosisi();
   }
}

//==================================================
// 🚀 BUKA POSISI DENGAN SL & TP LANGSUNG TERMASUK
//==================================================
bool BukaBeli()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pip = GetPipSize();
   
   // ✅ HITUNG SL & TP
   double sl = HitungSL_Beli(ask);
   double jarak_risk = ask - sl;
   double tp = ask + jarak_risk * RR_Ratio;
   
   g_SL_Aktif = sl;
   g_TP_Aktif = tp;
   
   MqlTradeRequest req={0}; MqlTradeResult res={0};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lot_Size;
   req.type=ORDER_TYPE_BUY; req.price=ask;
   req.sl=sl;   // ✅ SL LANGSUNG DIPASANG
   req.tp=tp;   // ✅ TP LANGSUNG DIPASANG
   req.magic=Magic_Number; req.type_filling=ORDER_FILLING_FOK;
   
   bool ok=OrderSend(req,res);
   if(ok) Print("✅ BELI | Harga:",ask," | 🛡️ SL:",sl," | 🎯 TP:",tp);
   else Print("❌ GAGAL BELI | Error:",GetLastError());
   return ok;
}

bool BukaJual()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip = GetPipSize();
   
   // ✅ HITUNG SL & TP
   double sl = HitungSL_Jual(bid);
   double jarak_risk = sl - bid;
   double tp = bid - jarak_risk * RR_Ratio;
   
   g_SL_Aktif = sl;
   g_TP_Aktif = tp;
   
   MqlTradeRequest req={0}; MqlTradeResult res={0};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lot_Size;
   req.type=ORDER_TYPE_SELL; req.price=bid;
   req.sl=sl;   // ✅ SL LANGSUNG DIPASANG
   req.tp=tp;   // ✅ TP LANGSUNG DIPASANG
   req.magic=Magic_Number; req.type_filling=ORDER_FILLING_FOK;
   
   bool ok=OrderSend(req,res);
   if(ok) Print("✅ JUAL | Harga:",bid," | 🛡️ SL:",sl," | 🎯 TP:",tp);
   else Print("❌ GAGAL JUAL | Error:",GetLastError());
   return ok;
}

//==================================================
// 🏠 UTAMA
//==================================================
void OnTick()
{
   ulong t; ENUM_ORDER_TYPE tipe;
   bool ada_posisi = CekPosisi(t, tipe);
   
   CekTargetHarian();
   
   if(ada_posisi)
   {
      // ✅ Pastikan SL tidak hilang
      static ulong last_ticket = 0;
      if(last_ticket != t)
      {
         last_ticket = t;
         double sl_aktif = PositionGetDouble(POSITION_SL);
         double tp_aktif = PositionGetDouble(POSITION_TP);
         Print("🛡️ SL Aktif: ", sl_aktif, " | 🎯 TP Aktif: ", tp_aktif);
      }
      return;
   }
   
   last_ticket = 0;
   g_SL_Aktif = 0;
   g_TP_Aktif = 0;
   
   if(!BolehTradingJam()) return;
   
   static datetime lilin_sebelum = 0;
   if(lilin_sebelum != iTime(_Symbol,_PERIOD,0))
   {
      lilin_sebelum = iTime(_Symbol,_PERIOD,0);
      DeteksiFVG();
      DeteksiOrderBlock();
   }
   
   double harga_sekarang = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // 🔵 BELI
   if(StrukturBerubah_Naik())
   {
      bool di_FVG = g_FVG.aktif && g_FVG.arah_beli && harga_sekarang>=g_FVG.bawah && harga_sekarang<=g_FVG.atas;
      bool di_OB = g_OB_Beli.aktif && MathAbs(harga_sekarang-g_OB_Beli.harga)<GetPipSize()*10;
      if(di_FVG || di_OB) { BukaBeli(); g_FVG.aktif=false; g_OB_Beli.aktif=false; return; }
   }
   
   // 🔴 JUAL
   if(StrukturBerubah_Turun())
   {
      bool di_FVG = g_FVG.aktif && !g_FVG.arah_beli && harga_sekarang>=g_FVG.bawah && harga_sekarang<=g_FVG.atas;
      bool di_OB = g_OB_Jual.aktif && MathAbs(harga_sekarang-g_OB_Jual.harga)<GetPipSize()*10;
      if(di_FVG || di_OB) { BukaJual(); g_FVG.aktif=false; g_OB_Jual.aktif=false; return; }
   }
}
//+------------------------------------------------------------------+
