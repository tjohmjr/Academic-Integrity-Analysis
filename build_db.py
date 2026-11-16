"""
build_db.py  -  rebuild academic_integrity.db from the CSVs in Data/.

  python3 build_db.py            create the database: SQLFiles/schema.sql + raw CSV load
  python3 build_db.py --run-all  also run the other scripts in SQLFiles/ in order
                                 and write every result table to results.txt

Uses only the Python standard library. Run it from the project folder.
"""
import csv, os, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "academic_integrity.db")
SQL = os.path.join(HERE, "SQLFiles")
DATA = os.path.join(HERE, "Data")
TABLES = {
    "student_nodes": "stg_student_nodes",
    "cheating_network_edges": "stg_cheating_network_edges",
    "plagiarism_cascades": "stg_plagiarism_cascades",
    "chatgpt_detection_results": "stg_chatgpt_detection_results",
    "ai_essay_submissions": "stg_ai_essay_submissions",
    "honor_code_violations": "stg_honor_code_violations",
    "assignment_design_efficacy": "stg_assignment_design_efficacy",
    "network_metrics": "stg_network_metrics",
    "false_positive_rates": "stg_false_positive_rates",
}
SCHEMA = "schema.sql"
SCRIPTS = ["transform.sql", "network_analysis.sql", "cascade_analysis.sql",
           "detector_audit.sql", "trends_and_design.sql",
           "views_and_queries.sql", "query_plans.sql"]


def read(name):
    with open(os.path.join(SQL, name), encoding="utf-8") as f:
        return f.read()


def split_statements(sql):
    stmts, buf = [], ""
    for line in sql.splitlines(keepends=True):
        buf += line
        if sqlite3.complete_statement(buf):
            if buf.strip():
                stmts.append(buf.strip())
            buf = ""
    if buf.strip():
        stmts.append(buf.strip())
    return [s for s in stmts if any(l.strip() and not l.strip().startswith("--")
                                    for l in s.splitlines())]


def fmt(v):
    if v is None:
        return "NULL"
    if isinstance(v, float):
        return f"{v:.6g}" if abs(v) < 1e6 else f"{v:.1f}"
    return str(v)


def table(cols, rows):
    data = [[fmt(v) for v in r] for r in rows]
    w = [max(len(str(c)), *(len(r[i]) for r in data)) if data else len(str(c))
         for i, c in enumerate(cols)]
    sep = "+" + "+".join("-" * (x + 2) for x in w) + "+"
    out = [sep, "| " + " | ".join(str(c).ljust(w[i]) for i, c in enumerate(cols)) + " |", sep]
    for r in data:
        out.append("| " + " | ".join(r[i].ljust(w[i]) for i in range(len(cols))) + " |")
    out.append(sep)
    return "\n".join(out)


def main():
    if os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    con.executescript(read(SCHEMA))
    for csv_name, tbl in TABLES.items():
        with open(os.path.join(DATA, csv_name + ".csv"), newline="", encoding="utf-8") as f:
            r = csv.reader(f)
            next(r)
            rows = [row for row in r if row]
        ph = ",".join("?" * len(rows[0]))
        con.executemany(f"INSERT INTO {tbl} VALUES ({ph})", rows)
        print(f"loaded {len(rows):>5} rows into {tbl}")
    con.commit()
    if "--run-all" in sys.argv:
        out = []
        for script in SCRIPTS:
            out.append(f"\n{'=' * 70}\n{script}\n{'=' * 70}")
            for st in split_statements(read(script)):
                cur = con.execute(st)
                if cur.description:
                    out.append(table([d[0] for d in cur.description], cur.fetchall()))
                    out.append("")
        con.commit()
        with open(os.path.join(HERE, "results.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(out))
        print("wrote results.txt")
    con.close()


if __name__ == "__main__":
    main()
