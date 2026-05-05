import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public class MetaCountRunnerClean {
    public static void main(String[] args) {
        try {
            if (args.length < 1) {
                System.err.println("NAT_CD is empty");
                return;
            }

            String natCd = args[0];

            Class.forName(ExecutorConf.getMeta_driver());

            try (Connection conn = createMetaConnection()) {
                String regTypeSummary = "";
                DailyChangeResult dailyChangeResult = new DailyChangeResult("", "");

                try {
                    regTypeSummary = getRegTypeSummary(conn, natCd);
                } catch (Exception e) {
                    System.err.println(e.getMessage());
                }

                try {
                    dailyChangeResult = getDailyChangeSummary(conn, natCd);
                } catch (Exception e) {
                    System.err.println(e.getMessage());
                }

                System.out.println("OK@@" + regTypeSummary + "@@" + dailyChangeResult.summary + "@@"
                        + dailyChangeResult.vvLogChange);
            }
        } catch (Exception e) {
            System.err.println(e.getMessage());
            System.out.println("DB_ERROR");
        }
    }

    private static DailyChangeResult getDailyChangeSummary(Connection conn, String natCd) throws Exception {
        int todayCount = 0;
        int yesterdayCount = 0;
        int beforeYesterdayCount = 0;

        try (PreparedStatement pstmt = conn.prepareStatement(getDailyCountSql())) {
            pstmt.setString(1, natCd);
            try (ResultSet rs = pstmt.executeQuery()) {
                if (rs.next()) {
                    todayCount = rs.getInt(1);
                    yesterdayCount = rs.getInt(2);
                    beforeYesterdayCount = rs.getInt(3);
                }
            }
        }

        List<String> dailyChangeBlocks = new ArrayList<>();

        if (todayCount > 0) {
            dailyChangeBlocks.add("[당일건수 " + String.format("%,d", todayCount) + "건]");
        }

        String vvLogChange = "";
        if (todayCount > 0 && yesterdayCount > 0) {
            int change = todayCount - yesterdayCount;
            vvLogChange = String.valueOf(change);
            dailyChangeBlocks.add("[당일-전일 증감건수 " + change + "건]");
        }

        if (todayCount > 0 && beforeYesterdayCount > 0) {
            dailyChangeBlocks.add("[당일-전전일 증감건수 " + (todayCount - beforeYesterdayCount) + "건]");
        }

        return new DailyChangeResult(String.join(" ", dailyChangeBlocks), vvLogChange);
    }

    private static Connection createMetaConnection() throws Exception {
        return DriverManager.getConnection(
                ExecutorConf.getMeta_jdbcUrl(),
                ExecutorConf.getMeta_user(),
                ExecutorConf.getMeta_password());
    }

    private static String getRegTypeSummary(Connection conn, String natCd) throws Exception {
        int cuCount = 0;
        int dCount = 0;

        try (PreparedStatement pstmt = conn.prepareStatement(getRegTypeCountSql())) {
            pstmt.setString(1, natCd);

            try (ResultSet rs = pstmt.executeQuery()) {
                while (rs.next()) {
                    String regType = rs.getString(1);
                    int count = rs.getInt(2);

                    if ("CU".equals(regType)) {
                        cuCount = count;
                    } else if ("D".equals(regType)) {
                        dCount = count;
                    }
                }
            }
        }

        return "CU : " + String.format("%,d", cuCount) + " / D : " + String.format("%,d", dCount);
    }

    private static String getRegTypeCountSql() {
        return ""
                + "SELECT reg_type, COUNT(*) \n"
                + "FROM wam_code \n"
                + "WHERE nat_cd = ? \n"
                + "  AND apl_dt >= DATE_FORMAT(CURRENT_DATE, '%Y%m%d') \n"
                + "GROUP BY reg_type \n";
    }

    private static String getDailyCountSql() {
        return ""
                + "SELECT \n"
                + "  SUM(CASE WHEN base_dt = DATE_FORMAT(CURRENT_DATE, '%Y%m%d') THEN 1 ELSE 0 END) AS today_cnt, \n"
                + "  SUM(CASE WHEN base_dt = DATE_FORMAT(DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY), '%Y%m%d') THEN 1 ELSE 0 END) AS yesterday_cnt, \n"
                + "  SUM(CASE WHEN base_dt = DATE_FORMAT(DATE_SUB(CURRENT_DATE, INTERVAL 2 DAY), '%Y%m%d') THEN 1 ELSE 0 END) AS before_yesterday_cnt \n"
                + "FROM vv_log \n"
                + "WHERE nat_cd = ? \n";
    }

    private static class DailyChangeResult {
        private final String summary;
        private final String vvLogChange;

        private DailyChangeResult(String summary, String vvLogChange) {
            this.summary = summary;
            this.vvLogChange = vvLogChange;
        }
    }
}
