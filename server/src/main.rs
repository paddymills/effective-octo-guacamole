use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use serde_json::{json, Value};
use tokio::sync::Mutex;

use sigmanest_interface::{
    batch::Batch,
    db::{
        self,
        api::{FeedbackEntry, Nest},
        exports::export_feedback,
    },
    Result,
};

#[derive(Debug, serde::Deserialize)]
struct ProgramUpdateParams {
    batch: String,
    state: ProgramState,
}

#[derive(Debug, serde::Deserialize)]
enum ProgramState {
    Initiated,
    Processing,
    Complete,
    Cancelled,
}

#[derive(Debug)]
struct AppState {
    pub db: db::DbPool,
    pub batches: Mutex<Option<Vec<Batch>>>,
}

impl AppState {
    pub async fn new() -> Self {
        Self {
            db: db::build_db_pool().await,
            batches: Mutex::new(None),
        }
    }
}

#[tokio::main]
async fn main() -> std::result::Result<(), std::io::Error> {
    fern::Dispatch::new()
        .format(|out, message, record| {
            out.finish(format_args!(
                "[{} {} {}] {}",
                humantime::format_rfc3339_seconds(std::time::SystemTime::now()),
                record.level(),
                record.target(),
                message
            ))
        })
        .level(log::LevelFilter::Error)
        .level_for("sigmanest_interface", log::LevelFilter::Trace)
        .chain(
            fern::Dispatch::new()
                .level(log::LevelFilter::Debug)
                .chain(std::io::stdout()),
        )
        .chain(
            fern::Dispatch::new().level(log::LevelFilter::Trace).chain(
                std::fs::OpenOptions::new()
                    .create(true)
                    .truncate(true)
                    .write(true)
                    .open("server.log")?,
            ),
        )
        .apply()
        .expect("failed to init logging");

    let state = Arc::new(AppState::new().await);

    // build our application with a single route
    let app = Router::new()
        .route("/", get(|| async { "root request not implemented yet" }))
        .route("/machines", get(get_machines))
        .route("/batches", get(get_batches))
        .route("/batches/:program", get(get_batches_for_program))
        .route("/:machine", get(get_programs))
        .route("/nest/:nest", get(get_nest).post(update_program))
        .route("/feedback", get(get_feedback))
        .with_state(state);

    // run our app with hyper, listening globally on port 3080
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3080").await?;
    axum::serve(listener, app).await
}

async fn get_machines(State(state): State<Arc<AppState>>) -> (StatusCode, Json<Value>) {
    log::debug!("Requested machines list");

    let state = Arc::clone(&state);

    let mut conn = state.db.get_owned().await.unwrap();
    let results = conn
        .simple_query("select distinct MachineName from ProgramMachine")
        .await;
    match results {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                let machines: Vec<String> = rows
                    .iter()
                    .map(|row| row.get::<&str, _>(0))
                    .map(|val| String::from(val.unwrap_or("")))
                    .collect();

                (StatusCode::OK, Json(json!(machines)))
            }
            Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(Value::Null)),
        },
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(Value::Null)),
    }
}

async fn get_batches(State(state): State<Arc<AppState>>) -> Result<(StatusCode, Json<Vec<Batch>>)> {
    log::debug!("Requested batches list");

    let state = Arc::clone(&state);
    let mut batches = state.batches.lock().await;

    if let None = *batches {
        // load batches from data source
        *batches = Some(Batch::get_batches()?);
    }

    Ok((StatusCode::OK, Json(batches.as_ref().unwrap().clone())))
}

async fn get_batches_for_program(
    State(state): State<Arc<AppState>>,
    Path(program): Path<String>,
) -> Result<(StatusCode, Json<Vec<Batch>>)> {
    log::debug!("Requested batches list for program `{}`", program);

    let state = Arc::clone(&state);

    let mut batches = state.batches.lock().await;
    if let None = *batches {
        // load batches from data source
        *batches = Some(Batch::get_batches()?);
    }

    let mut conn = state.db.get_owned().await.unwrap();
    let nest = Nest::get(&mut conn, &program).await?;

    // TODO: handle nested on singleton sheet

    let mm_batches = batches
        .as_ref()
        .unwrap()
        .iter()
        .filter(|bat| bat.sheet_name == nest.sheet.sheet_name)
        .map(|bat| bat.clone())
        .collect();

    Ok((StatusCode::OK, Json(mm_batches)))
}

async fn get_feedback(
    State(state): State<Arc<AppState>>,
) -> Result<(StatusCode, Json<Vec<FeedbackEntry<Nest>>>)> {
    log::debug!("Requested feedback");

    let state = Arc::clone(&state);

    let feedback = export_feedback(state.db.clone()).await?;

    Ok((StatusCode::OK, Json(feedback)))
}

async fn get_programs(
    State(state): State<Arc<AppState>>,
    Path(machine): Path<String>,
) -> (StatusCode, Json<Value>) {
    log::debug!("Requested programs for machine {}", machine);

    let state = Arc::clone(&state);

    let mut conn = state.db.get_owned().await.unwrap();
    let results = conn
        .query(
            r#"
SELECT DISTINCT
    ProgramName,
    CuttingTime,
    rpt.Repeats
FROM ProgramMachine
INNER JOIN (
    SELECT
		ProgramName AS p,
		COUNT(RepeatID) AS Repeats
    FROM Program
    WHERE NOT EXISTS (
        SELECT 1
        FROM TransAct
        WHERE TransType = 'SN70'
        AND TransAct.ProgramName=Program.ProgramName
        AND TransAct.ProgramRepeat=Program.RepeatId
    )
    GROUP BY ProgramName
) AS rpt
    ON rpt.p=ProgramMachine.ProgramName
WHERE MachineName=@P1
AND rpt.Repeats > 0
            "#,
            &[&machine],
        )
        .await;
    match results {
        Ok(stream) => match stream.into_first_result().await {
            Ok(rows) => {
                let programs: Vec<Value> = rows
                    .iter()
                    .map(|row| {
                        json!({
                            "program": row.get::<&str, _>("ProgramName").unwrap(),
                            "repeats": row.get::<i32, _>("Repeats").unwrap(),
                            "cuttingTime": row.get::<f64, _>("CuttingTime").unwrap()
                        })
                    })
                    .collect();

                (StatusCode::OK, Json(json!(programs)))
            }
            Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(Value::Null)),
        },
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, Json(Value::Null)),
    }
}

async fn get_nest(
    State(state): State<Arc<AppState>>,
    Path(program): Path<String>,
) -> Result<(StatusCode, Json<Value>)> {
    log::debug!("Requested program {}", program);

    let state = Arc::clone(&state);
    let mut conn = state.db.get_owned().await.unwrap();
    let nest = Nest::get(&mut conn, &program).await?;

    log::debug!("Nest found");
    Ok((StatusCode::OK, Json(serde_json::to_value(nest).unwrap())))
}

async fn update_program(
    State(state): State<Arc<AppState>>,
    Path(program): Path<String>,
    Json(params): Json<ProgramUpdateParams>,
) -> (StatusCode, Json<Value>) {
    // TODO: log processing changes to database

    match params.state {
        ProgramState::Initiated => log::trace!("Program {} initiated", program),
        ProgramState::Processing => {
            // TODO: move NC"
            log::trace!(
                "Program {} is moved to processing with batch {}",
                program,
                params.batch
            );
        }
        ProgramState::Complete => {
            log::info!("Program {} complete with batch {}", program, params.batch);

            // issue SimTrans update
            let state = Arc::clone(&state);
            let mut conn = state.db.get_owned().await.unwrap();
            let update = conn
                .execute(
                    r#"
INSERT INTO TransAct(TransType,District,ProgramName,ProgramRepeat)
VALUES (
    SELECT TOP 1
        'SN70',1,@P1,RepeatId
    FROM Program
    WHERE ProgramName=@P1
)
                    "#,
                    &[&program],
                )
                .await;

            if let Err(e) = update {
                log::error!("Failed to push program update to SimTrans");
                log::error!("{:#?}", e);
            }
        }
        ProgramState::Cancelled => log::trace!("Program {} cancelled", program),
    }

    (StatusCode::CREATED, Json(Value::Null))
}
