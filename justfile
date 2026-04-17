set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

[private]
default:
    @just --list

demo target *args:
    python scripts/demo.py {{ target }} {{ args }}

[working-directory('heatswap')]
heatswap:
    cargo build --release
    cp target/build/cleanup.exe \\hssieng\sndatadev\_simtrans
    cp target/build/cleanup.exe \\hssieng\sndataqas\_simtrans

gensql *args: clean
    python gen_proc.py {{ args }}

sql env *cmd:
    @sqlcmd -S {{ if env == "prd" { "HSSSNData" } else { "hiisqlserv6" } }} -E -d SNInter{{ capitalize(env) }} -b -Q {{ quote(cmd) }}

cfg env:
    @just sql {{ env }} "select * from sap.InterCfgState"

view env *view:
    @just sql {{ env }} "select * from {{ view }}"

deploy:
    @just gensql --deploy --migrate dev
    @just cfg dev
    @just gensql --deploy --migrate qas
    @just cfg qas
    @just gensql --deploy --migrate prd
    @just cfg prd

convert *args: clean
    python convert_bom.py {{ args }}

@clean:
    rm log/*
    rm dist/*_SapInter_*.sql
    rm conversion/output/*.ready
