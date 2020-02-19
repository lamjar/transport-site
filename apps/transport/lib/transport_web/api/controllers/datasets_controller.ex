defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  alias Helpers
  alias OpenApiSpex.Operation
  alias DB.{AOM, Commune, Dataset, Region, Repo}
  alias TransportWeb.API.Schemas.{AutocompleteResponse, DatasetsResponse}
  import Ecto.{Query}

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec datasets_operation() :: Operation.t()
  def datasets_operation do
    %Operation{
      tags: ["datasets"],
      summary: "Show datasets and its resources",
      description: "For every dataset, show its associated resources, url and validity date",
      operationId: "API.DatasetController.datasets",
      parameters: [],
      responses: %{
        200 => Operation.response("Dataset", "application/json", DatasetsResponse)
      }
    }
  end

  def datasets(%Plug.Conn{} = conn, _params) do
    data =
      %{"type" => "public-transit"}
      |> Dataset.list_datasets()
      |> Repo.all()
      |> Repo.preload([:resources, :aom])
      |> Enum.map(&transform_dataset/1)

    render(conn, %{data: data})
  end

  @spec by_id_operation() :: Operation.t()
  def by_id_operation do
    %Operation{
      tags: ["datasets"],
      summary: "Show given dataset and its resources",
      description: "For one dataset, show its associated resources, url and validity date",
      operationId: "API.DatasetController.datasets_by_id",
      parameters: [Operation.parameter(:id, :path, :string, "id")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", DatasetsResponse)
      }
    }
  end

  def by_id(%Plug.Conn{} = conn, %{"id" => id}) do
    Dataset
    |> Repo.get_by(datagouv_id: id)
    |> Repo.preload([:resources, :aom])
    |> case do
      %Dataset{} = dataset ->
        conn
        |> assign(:data, transform_dataset_with_detail(dataset))
        |> render()

      nil ->
        conn
        |> put_status(404)
        |> render(%{errors: "dataset not found"})
    end
  end

  defp transform_dataset(dataset) do
    %{
      "datagouv_id" => dataset.datagouv_id,
      # to help discoverability, we explicitly add the datagouv_id as the id
      # (since it's used in /dataset/:id)
      "id" => dataset.datagouv_id,
      "title" => dataset.spatial,
      "created_at" => dataset.created_at,
      "updated" => Helpers.last_updated(dataset.resources),
      "resources" => Enum.map(dataset.resources, &transform_resource/1),
      "aom" => transform_aom(dataset.aom),
      "type" => dataset.type,
      "publisher" => get_publisher(dataset)
    }
  end

  defp get_publisher(dataset) do
    %{
      "name" => dataset.organization,
      "type" => "organization"
    }
  end

  defp transform_dataset_with_detail(dataset) do
    dataset
    |> transform_dataset
    |> Map.put("history", Dataset.history_resources(dataset))
  end

  defp transform_resource(resource) do
    %{
      "title" => resource.title,
      "updated" => Helpers.format_datetime(resource.last_update),
      "url" => resource.latest_url,
      "end_calendar_validity" => resource.metadata["end_date"],
      "start_calendar_validity" => resource.metadata["start_date"],
      "format" => resource.format,
      "content_hash" => resource.content_hash
    }
  end

  defp transform_aom(nil), do: %{"name" => nil}

  defp transform_aom(aom) do
    %{
      "name" => aom.nom,
      "siren" => aom.siren
    }
  end

  defp get_result_url(%{id: id, type: "commune"}) do
    "/datasets/commune/#{id}"
  end

  defp get_result_url(%{id: id, type: "region"}) do
    "/datasets/region/#{id}"
  end

  defp get_result_url(%{id: id, type: "aom"}) do
    "/datasets/aom/#{id}"
  end

  @spec autocomplete(Plug.Conn.t(), map) :: Plug.Conn.t()
  def autocomplete(%Plug.Conn{} = conn, %{"q" => query}) do
    communes =
      Repo.all(
        from(c in Commune,
          where: ilike(c.nom(), ^"%#{query}%"),
          order_by: [asc: fragment("levenshtein(?, ?)", c.nom, ^query), asc: c.nom],
          select: %{nom: c.nom, id: c.insee, type: "commune"},
          limit: 5
        )
      )

    regions =
      Repo.all(
        from(c in Region,
          where: ilike(c.nom(), ^"%#{query}%"),
          select: %{nom: c.nom, id: c.insee, type: "region"},
          limit: 2
        )
      )

    aom =
      Repo.all(
        from(c in AOM,
          where: ilike(c.nom(), ^"%#{query}%"),
          select: %{nom: c.nom, id: c.id, type: "aom"},
          limit: 2
        )
      )

    results =
      (communes ++ regions ++ aom)
      |> Enum.map(&%{name: &1.nom, type: &1.type, url: get_result_url(&1)})

    conn
    |> assign(:data, results)
    |> render()
  end

  @spec autocomplete_operation() :: Operation.t()
  def autocomplete_operation do
    %Operation{
      tags: ["datasets"],
      summary: "Autocomplete search for datasets",
      description: "Given a search input, return potentialy corresponding results with the associated url",
      operationId: "API.DatasetController.datasets_autocomplete",
      parameters: [Operation.parameter(:q, :path, :string, "query")],
      responses: %{
        200 => Operation.response("Dataset", "application/json", AutocompleteResponse)
      }
    }
  end
end
