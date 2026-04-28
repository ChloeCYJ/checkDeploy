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
                String dailySummary = getDailySummary(conn, natCd);
                String regTypeSummary = "";

                try {
                    regTypeSummary = getRegTypeSummary(conn, natCd);
                } catch (Exception e) {
                    System.err.println(e.getMessage());
                }

                if (regTypeSummary == null || regTypeSummary.isEmpty()) {
                    System.out.println(dailySummary);
                } else {
                    System.out.println(dailySummary + "@@" + regTypeSummary);
                }
            }
        } catch (Exception e) {
            System.err.println(e.getMessage());
            System.out.println("DB_ERROR");
        }
    }

    private static Connection createMetaConnection() throws Exception {
        return DriverManager.getConnection(
                ExecutorConf.getMeta_jdbcUrl(),
                ExecutorConf.getMeta_user(),
                ExecutorConf.getMeta_password());
    }

    private static String getDailySummary(Connection conn, String natCd) throws Exception {
        try (PreparedStatement pstmt = conn.prepareStatement(getDailyCountSql())) {
            pstmt.setString(1, natCd);

            try (ResultSet rs = pstmt.executeQuery()) {
                List<String> result = new ArrayList<>();

                while (rs.next()) {
                    result.add(rs.getString(1) + " " + rs.getInt(2) + "건");
                }

                return String.join("|", result);
            }
        }
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

    private static String getDailyCountSql() {
        return ""
                + "SELECT base_dt, COUNT(*) \n"
                + "FROM vv_log \n"
                + "WHERE nat_cd = ? \n"
                + "GROUP BY base_dt \n"
                + "ORDER BY base_dt \n";
    }

    private static String getRegTypeCountSql() {
        return ""
                + "SELECT reg_type, COUNT(*) \n"
                + "FROM wam_code \n"
                + "WHERE nat_cd = ? \n"
                + "  AND apl_dt >= DATE_FORMAT(CURRENT_DATE, '%Y%m%d') \n"
                + "GROUP BY reg_type \n";
    }
}
