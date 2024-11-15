use bb8::PooledConnection;
use bb8_tiberius::ConnectionManager;

/// Convenience export of database Pool type
pub type DbPool = bb8::Pool<bb8_tiberius::ConnectionManager>;
pub type SqlConn<'a> = PooledConnection<'a, ConnectionManager>;

/// Builds a connection pool for a database
pub async fn build_db_pool() -> DbPool {
    log::trace!("** init db pool");

    // sigmanest interface dev
    let config = {
        log::debug!("using development database config");
        let mut config = tiberius::Config::new();
        config.host("HIISQLSERV6");
        config.database("SNDBaseISap");

        // use sql authentication
        let user = std::env::var("SNDB_USER").unwrap();
        let pass = std::env::var("SNDB_PWD").unwrap();
        config.authentication(tiberius::AuthMethod::sql_server(user, pass));
        config.trust_cert();

        config
    };

    // production
    // let config = {
    //     log::debug!("using development database config");
    //     let mut config = tiberius::Config::new();
    //     config.host(std::env::var("SndbServer").unwrap());
    //     config.database(std::env::var("SndbDatabase").unwrap());

    //     // use windows authentication
    //     config.authentication(tiberius::AuthMethod::Integrated);
    //     config.trust_cert();

    //     config
    // };

    let mgr = match bb8_tiberius::ConnectionManager::build(config) {
        Ok(conn_mgr) => conn_mgr,
        Err(_) => panic!("ConnectionManager failed to connect to database"),
    };

    log::trace!("** > db connection Manager built");

    let pool = match bb8::Pool::builder().max_size(8).build(mgr).await {
        Ok(pool) => pool,
        Err(_) => panic!("database pool failed to build"),
    };

    log::trace!("** > db pool built");

    log::info!("database connected");
    pool
}
