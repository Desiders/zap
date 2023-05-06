use std::convert::Infallible;

use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Request, Response, Server};

async fn handle(_: Request<Body>) -> Result<Response<Body>, Infallible> {
    Ok(Response::new("Hello from Rust!".into()))
}

#[tokio::main(worker_threads = 4)]
pub async fn main() {
    let addr = ([127, 0, 0, 1], 7878).into();

    Server::bind(&addr)
        .serve(make_service_fn(|_conn| async {
            Ok::<_, Infallible>(service_fn(handle))
        }))
        .await
        .unwrap();
}
