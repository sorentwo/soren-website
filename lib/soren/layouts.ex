defmodule Soren.Layouts do
  use Soren.Web, :html

  attr :page_title, :string, default: ""
  attr :page_dark?, :boolean, default: false

  attr :page_description, :string,
    default: "Soren is Shannon and Parker. We're the people behind Oban, Oban Web, and Oban Pro."

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="author" content="Parker and Shannon Selbert" />
        <meta name="description" content={@page_description} />

        <.live_title suffix=" • Soren"><%= @page_title %></.live_title>

        <meta property="og:title" content={@page_title} />
        <meta property="og:description" content={@page_description} />
        <meta property="og:locale" content="en_US" />
        <meta property="og:type" content="article" />
        <meta property="og:site_name" content="Soren Blog" />
        <meta property="og:url" content={current_url(@conn)} />
        <meta property="og:image" content={~p"/images/soren-og-card.jpg"} />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:creator" content="@sorentwo" />
        <meta name="twitter:site" content="@sorentwo" />

        <link
          rel="alternate"
          type="application/atom+xml"
          href={~p"/feed.xml"}
          title="Soren Blog » Feed"
        />

        <link phx-track-static rel="icon" type="image/svg+xml" href="/favicon.svg" />
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
      </head>
      <body class={[
        "min-h-screen flex flex-col font-sans antialiased",
        if(@page_dark?, do: "bg-cyan-950 text-gray-100", else: "bg-gray-100 text-gray-900")
      ]}>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  attr :page_dark?, :boolean, default: false

  def app(assigns) do
    ~H"""
    <div class="flex-1">
      <.header {assigns} />
      <%= @inner_content %>
    </div>
    <.footer {assigns} />
    """
  end

  def header(assigns) do
    ~H"""
    <header class="max-w-screen-sm mx-auto py-6 px-6 md:px-0 flex justify-between">
      <a class="flex items-center space-x-2" href="/" title="Soren Home">
        <svg
          class={["w-8 h-8", if(@page_dark?, do: "fill-gray-200", else: "fill-gray-800")]}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 254 254"
        >
          <path d="M253.52 21.272a3.974 3.974 0 0 0-1.156-2.788L235.516 1.636a3.94 3.94 0 0 0-5.574 0L201.908 29.67C181.176 13.69 155.2 4.184 127 4.184 59.172 4.184 4.184 59.172 4.184 127c0 28.2 9.506 54.176 25.484 74.908L1.636 229.94a3.972 3.972 0 0 0-1.156 2.79 3.97 3.97 0 0 0 1.156 2.786l16.85 16.852a3.965 3.965 0 0 0 2.788 1.154c1.04 0 2.052-.42 2.788-1.154l28.032-28.032c20.73 15.976 46.708 25.48 74.908 25.48 67.828 0 122.814-54.984 122.814-122.814 0-28.2-9.504-54.178-25.482-74.91l28.032-28.032a3.978 3.978 0 0 0 1.154-2.788ZM55.426 127c0-19.12 7.446-37.092 20.964-50.61C89.908 62.872 107.882 55.426 127 55.426c13.716 0 26.844 3.832 38.158 10.992l-98.742 98.74c-7.158-11.314-10.99-24.442-10.99-38.158Zm143.148 0c0 19.118-7.446 37.09-20.964 50.61-13.518 13.52-31.492 20.966-50.61 20.966-13.716 0-26.844-3.836-38.16-10.992l98.742-98.744c7.158 11.316 10.992 24.444 10.992 38.16Z" />
        </svg>
        <span class="font-semibold">Soren</span>
      </a>

      <div class={[
        "flex justify-center space-x-3",
        if(@page_dark?, do: "fill-gray-300 text-gray-400", else: "fill-gray-600 text-gray-500")
      ]}>
        <a
          title="Email"
          href="mailto:soren@sorentwo.com"
          class={[
            "w-5 h-5 rounded-full transition-transform hover:scale-125",
            if(@page_dark?, do: "bg-gray-300", else: "bg-gray-600")
          ]}
        >
          <svg
            class={["w-5 h-5", if(@page_dark?, do: "fill-cyan-950", else: "fill-gray-50")]}
            viewBox="0 0 20 20"
          >
            <path
              fill-rule="evenodd"
              d="M5.404 14.596A6.5 6.5 0 1 1 16.5 10a1.25 1.25 0 0 1-2.5 0 4 4 0 1 0-.571 2.06A2.75 2.75 0 0 0 18 10a8 8 0 1 0-2.343 5.657.75.75 0 0 0-1.06-1.06 6.5 6.5 0 0 1-9.193 0ZM10 7.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5Z"
              clip-rule="evenodd"
            />
          </svg>
        </a>

        <a
          title="Github"
          href="https://github.com/sorentwo"
          class="transition-transform hover:scale-125"
        >
          <svg class="w-5 h-5" viewBox="0 0 98 96">
            <path
              fill-rule="evenodd"
              clip-rule="evenodd"
              d="M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z"
            />
          </svg>
        </a>
        <a title="Feed" href={~p"/feed.xml"} class="transition-transform hover:scale-125">
          <svg class="w-5 h-5" viewBox="0 0 16 16">
            <path
              d="M12.502 15.316h2.814C15.316 7.247 8.752.678.684.678v2.807c6.515 0 11.818 5.309 11.818 11.831Zm-9.87.005a1.944 1.944 0 0 0 1.951-1.942 1.95 1.95 0 0 0-3.899 0c0 1.075.873 1.942 1.948 1.942Zm4.895-.004h2.818c0-5.329-4.335-9.664-9.662-9.664v2.806c1.827 0 3.545.714 4.838 2.009a6.81 6.81 0 0 1 2.006 4.849Z"
              fill-rule="nonzero"
            />
          </svg>
        </a>
      </div>
    </header>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer class="text-gray-500 py-6 px-6 md:px-0">
      <p class="mt-3 text-center text-sm">&copy; 2008&mdash; Soren, LLC</p>
    </footer>
    """
  end
end
