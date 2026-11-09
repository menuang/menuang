//+------------------------------------------------------------------+
//|                                                    RiskGuard.mqh |
//|                                  Menuang — Ekosistem Mesin Uang  |
//|                                       https://github.com/menuang |
//+------------------------------------------------------------------+
#property copyright "Menuang"
#property link      "https://github.com/menuang"
#property strict

//+------------------------------------------------------------------+
//| Enum Status Risiko Unit Mesin Uang                               |
//+------------------------------------------------------------------+
enum ENUM_RISK_STATUS
  {
   RISK_OK = 0,               // Aman: Diizinkan membuka posisi baru
   RISK_EARLY_WARNING = 1,    // Rugi harian >= 15%: Berhenti buka posisi baru
   RISK_DAILY_LIMIT_HIT = 2,  // Rugi harian >= 50%: Tutup semua & berhenti
   RISK_MAX_DD_HIT = 3        // Drawdown kumulatif >= 70%: Matikan unit & evaluasi
  };

//+------------------------------------------------------------------+
//| Class CRiskGuard: Proteksi Batas Rugi Harian & Drawdown Kumulatif|
//+------------------------------------------------------------------+
class CRiskGuard
  {
private:
   double            m_earlyWarningPct;   // Peringatan dini (default 15%)
   double            m_maxDailyLossPct;   // Batas harian mutlak (default 50%)
   double            m_maxCumulativeDDPct;// Batas kumulatif (default 70%)
   double            m_initialModal;      // Modal awal / puncak ekuitas unit
   double            m_dailyStartBalance; // Saldo awal hari ini
   datetime          m_currentDay;        // Tanggal pelacakan harian

public:
                     CRiskGuard(double earlyWarningPct = 15.0,
                                double maxDailyLossPct = 50.0,
                                double maxCumulativeDDPct = 70.0,
                                double initialModal = 0.0)
     {
      m_earlyWarningPct    = earlyWarningPct;
      m_maxDailyLossPct    = maxDailyLossPct;
      m_maxCumulativeDDPct = maxCumulativeDDPct;
      m_initialModal       = (initialModal > 0.0) ? initialModal : AccountInfoDouble(ACCOUNT_BALANCE);
      m_dailyStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      m_currentDay         = GetStartOfDay(TimeCurrent());
     }

   //--- Perbarui acuan saldo harian saat pergantian hari server
   void              UpdateDailyAnchor()
     {
      datetime today = GetStartOfDay(TimeCurrent());
      if(today != m_currentDay)
        {
         m_currentDay        = today;
         m_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(m_dailyStartBalance > m_initialModal)
            m_initialModal = m_dailyStartBalance;
        }
     }

   //--- Hitung persentase kerugian hari ini (berdasarkan floating equity + realized)
   double            GetDailyLossPct()
     {
      UpdateDailyAnchor();
      if(m_dailyStartBalance <= 0.0)
         return 0.0;
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double loss          = m_dailyStartBalance - currentEquity;
      if(loss <= 0.0)
         return 0.0;
      return (loss / m_dailyStartBalance) * 100.0;
     }

   //--- Hitung persentase drawdown kumulatif dari modal awal / puncak
   double            GetCumulativeDrawdownPct()
     {
      if(m_initialModal <= 0.0)
         return 0.0;
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dd            = m_initialModal - currentEquity;
      if(dd <= 0.0)
         return 0.0;
      return (dd / m_initialModal) * 100.0;
     }

   //--- Evaluasi status risiko 3 lapis Menuang
   ENUM_RISK_STATUS  EvaluateRisk()
     {
      double cumDD     = GetCumulativeDrawdownPct();
      double dailyLoss = GetDailyLossPct();

      if(cumDD >= m_maxCumulativeDDPct)
         return RISK_MAX_DD_HIT;

      if(dailyLoss >= m_maxDailyLossPct)
         return RISK_DAILY_LIMIT_HIT;

      if(dailyLoss >= m_earlyWarningPct)
         return RISK_EARLY_WARNING;

      return RISK_OK;
     }

   //--- Apakah diizinkan membuka posisi baru?
   bool              CanOpenNewPosition()
     {
      return (EvaluateRisk() == RISK_OK);
     }

   //--- Helper awal hari (00:00:00)
   datetime          GetStartOfDay(datetime t)
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 0;
      dt.min  = 0;
      dt.sec  = 0;
      return StructToTime(dt);
     }
  };
//+------------------------------------------------------------------+
