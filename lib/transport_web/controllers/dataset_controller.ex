defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData
  alias Transport.Datagouvfr.Authentication

  def index(conn, _params) do
    conn
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end

  def details(conn, %{"slug" => slug}) do
    slug
    |> ReusableData.get_dataset(:with_celery_task)
    |> case do
      nil ->
        render(conn, "error.html")
      dataset ->
        conn
        |> assign(:dataset, dataset)
        |> assign(:nb_errors, ReusableData.count_errors(dataset))
        |> assign(:nb_warnings, ReusableData.count_warnings(dataset))
        |> assign(:nb_notices, ReusableData.count_notices(dataset))
        |> assign(:datasetid, ReusableData.get_dataset_id(conn, dataset))
        |> assign(:datagouvfrsite, Application.get_env(:oauth2, Authentication)[:site])
        |> render("details.html")
    end
  end
end
