from argparse import ArgumentParser
from glob import glob
from os import path, mkdir
import subprocess
import re

ENV_CONFIG = {
    # "SimTrans Env": [("Sigmanest Env", "District", "LogProcedureCalls")],
    # SimTrans/Sigmanest Env maps to which database said Env is on
    #   for example, "Dev" maps to SNDBaseDev
    "Dev": [
        ("Qas", 4, True),
        ("Dev", 3, True),
    ],
    "Prd": [
        ("Prd", 5, False),
    ],
    # local
    "Sbx": [
        ("Sbx", 64, True),
    ],
}
CREATE_FILES = [
    "SapInter_OysSchema.sql",
    "SapInter_HssSchema.sql",
    "SapInter_LogsSchema.sql",
]
DEPLOY_CONFIG = {
    "Dev": "hiisqlserv6",
    "Qas": "hiisqlserv6",
    "Prd": "HSSSNData",
    "Sbx": "W10286\\SIGMANEST",
}
DEPLOY_FILES = [
    "SapInter_DebugProc.sql",
    "SapInter_Proc.sql",
    "SapInter_Views.sql",
    "SapInter_CdsProc.sql",
]

INTER_DB = re.compile("SNInterDev")
SIMTRANS_DB = re.compile(r"SNDBaseDev(\.dbo\.TransAct)")
SIGMA_DB = re.compile(r"SNDBaseDev(\.\w+\.(?!TransAct)\w+)")
CONFIG_DISTRICT = re.compile(r"(DECLARE @district INT =) 1;")
CONFIG_LOGGING = re.compile(r"(DECLARE @do_logging BIT =) 0;")
CONFIG_ENV = re.compile(r"(DECLARE @env_name VARCHAR\(8\) =) 'Qas';")

schema_dir = path.join(path.dirname(__file__), "schema")


def generate(env, district, do_logging, simtrans):
    try:
        mkdir("dist")
    except FileExistsError:
        pass

    for f in glob("SapInter_*.sql", root_dir=schema_dir):
        with open(path.join(schema_dir, f), "r") as sql_file:
            sql = sql_file.read()

        sql = INTER_DB.sub(f"SNInter{env}", sql)
        sql = SIMTRANS_DB.sub(f"SNDBase{simtrans}\\1", sql)
        sql = SIGMA_DB.sub(f"SNDBase{env}\\1", sql)

        if f == "SapInter_HssSchema.sql":
            sql = CONFIG_DISTRICT.sub(f"\\1 {district};", sql)
            sql = CONFIG_LOGGING.sub(f"\\1 {int(do_logging)};", sql)
            sql = CONFIG_ENV.sub(f"\\1 '{env}';", sql)

        with open(path.join("dist", f"{env}_{f}"), "w") as sql_file:
            sql_file.write(sql)


def deploy(sqlfile, env, success=None):
    """Deploys the generated SQL files to the database."""

    try:
        subprocess.run(
            [
                "sqlcmd",
                "-S",  # SQL Server instance
                DEPLOY_CONFIG[env],
                "-E",  # Use Windows Authentication
                "-b",  # return errorlevel 1 on error
                "-i",  # Input file
                sqlfile,
                "-o",  # Output file
                sqlfile.replace("dist", "log").replace(".sql", ".log"),
            ],
            check=True,
        )
        print(success or f"🚀 {sqlfile} 🎯 {env}")
    except Exception as e:
        print(f"💥 {sqlfile} 💫 {env}")
        raise e


def main():
    default_deploy = map(str.lower, DEPLOY_CONFIG.keys() - {"Sbx"})

    parser = ArgumentParser(
        description="Generate and deploy SQL procedures for different environments."
    )
    parser.add_argument(
        "--create", action="store_true", help="Create the database schema."
    )
    parser.add_argument(
        "--deploy",
        action="store_true",
        help="Deploy the generated SQL files to the database.",
    )
    parser.add_argument(
        "--migrate", action="store_true", help="Deploy migration files."
    )
    parser.add_argument(
        "env",
        nargs="*",
        default=list(default_deploy),
        help="Specify the environments to deploy/migrate.",
    )
    parser.add_argument(
        "-v", "--verbose", action="count", help="Increase output verbosity."
    )
    args = parser.parse_args()

    for simtrans, envs in ENV_CONFIG.items():
        for env in envs:
            generate(*env, simtrans)

    for env in map(str.capitalize, args.env):
        if args.create:
            for fn in CREATE_FILES:
                sql = path.join("dist", f"{env}_{fn}")
                try:
                    deploy(sql, env)
                except Exception as e:
                    if args.verbose:
                        print(e)
        if args.migrate:
            sql = path.join("dist", f"{env}_SapInter_Migrations.sql")
            deploy(sql, env, success=f"✈️ {env} Migrations deployed successfully!")
        if args.deploy:
            for fn in DEPLOY_FILES:
                sql = path.join("dist", f"{env}_{fn}")
                try:
                    deploy(sql, env)
                except Exception as e:
                    if args.verbose:
                        print(e)


if __name__ == "__main__":
    main()
