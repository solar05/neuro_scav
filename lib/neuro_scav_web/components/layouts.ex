defmodule NeuroScavWeb.Layouts do
  @moduledoc """
  Layouts of the application, templates are in the `layouts` directory.

  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use NeuroScavWeb, :controller` and
  `use NeuroScavWeb, :live_view`.
  """
  use NeuroScavWeb, :html

  embed_templates "layouts/*"
end
