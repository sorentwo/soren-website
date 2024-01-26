defmodule Soren.Layouts do
  use Soren.Web, :html

  # TODO: Add feed
  # TODO: Use these
  # <meta property="og:title" content={title(@conn)} />
  # <meta property="og:description" content={description(@conn)} />
  # <meta property="og:locale" content="en_US" />
  # <meta property="og:type" content="article" />
  # <meta property="og:site_name" content="Oban Pro" />
  # <meta property="og:url" content={current_url(@conn)} />
  # <meta property="og:image" content={seo_image(@conn)} />

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="author" content="Parker and Shannon Selbert" />
        <meta
          name="description"
          content="Soren is the partnership of Shannon and Parker Selbert. We're the people behind Oban, Oban Web, and Oban Pro."
        />

        <.live_title suffix=" · Soren"><%= assigns[:page_title] %></.live_title>

        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:creator" content="@sorentwo" />
        <meta name="twitter:site" content="@sorentwo" />

        <link phx-track-static rel="icon" type="image/svg+xml" href="/favicon.svg" />
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
      </head>
      <body class="antialiased">
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <.header />
    <main><%= @inner_content %></main>
    <.footer />
    """
  end

  def header(assigns) do
    ~H"""
    <header>
      <%= if false do %>
        <a class="header-link--logo" href="/" title="Soren Home">
          <svg
            class="header-logo"
            width="24px"
            height="24px"
            viewBox="0 0 254 254"
            version="1.1"
            xmlns="http://www.w3.org/2000/svg"
            xmlns:xlink="http://www.w3.org/1999/xlink"
          >
            <g id="soren-logo" fill="none" fill-rule="nonzero">
              <path
                d="M253.52,21.272 C253.52,20.234 253.098,19.22 252.364,18.484 L235.516,1.636 C233.976,0.096 231.48,0.096 229.942,1.636 L201.908,29.67 C181.176,13.69 155.2,4.184 127,4.184 C59.172,4.184 4.184,59.172 4.184,127 C4.184,155.2 13.69,181.176 29.668,201.908 L1.636,229.94 C0.902,230.674 0.48,231.69 0.48,232.73 C0.48,233.768 0.902,234.78 1.636,235.516 L18.486,252.368 C19.22,253.102 20.234,253.522 21.274,253.522 C22.314,253.522 23.326,253.102 24.062,252.368 L52.094,224.336 C72.824,240.312 98.802,249.816 127.002,249.816 C194.83,249.816 249.816,194.832 249.816,127.002 C249.816,98.802 240.312,72.824 224.334,52.092 L252.366,24.06 C253.098,23.326 253.52,22.31 253.52,21.272 Z M55.426,127 C55.426,107.88 62.872,89.908 76.39,76.39 C89.908,62.872 107.882,55.426 127,55.426 C140.716,55.426 153.844,59.258 165.158,66.418 L66.416,165.158 C59.258,153.844 55.426,140.716 55.426,127 Z M198.574,127 C198.574,146.118 191.128,164.09 177.61,177.61 C164.092,191.13 146.118,198.576 127,198.576 C113.284,198.576 100.156,194.74 88.84,187.584 L187.582,88.84 C194.74,100.156 198.574,113.284 198.574,127 Z"
                id="Shape"
              >
              </path>
            </g>
          </svg>
          <span class="header-type">Soren</span>
        </a>
      <% end %>

      <nav id="header-nav" class="header-nav">
        <a class="header-link" href="/blog">Blog</a>
        <a class="header-link" href="https://getoban.pro">Oban</a>
        <a class="header-link" href="/contact" class="contact">Contact</a>
      </nav>
    </header>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer>
      <p class="footer__copyright">
        &copy; 2008&mdash; Soren, LLC
      </p>

      <nav class="footer__links">
        <a title="SorenTwo's Github" href="https://github.com/sorentwo">
          <svg
            width="24px"
            height="24px"
            viewBox="0 0 33 32"
            version="1.1"
            xmlns="http://www.w3.org/2000/svg"
            xmlns:xlink="http://www.w3.org/1999/xlink"
          >
            <g id="Page-1" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
              <g id="GitHub-Mark" transform="translate(-128.000000, -317.000000)" fill="#FFFFFE">
                <path
                  d="M144.288,317 C135.294,317 128,324.293 128,333.29 C128,340.487 132.667,346.592 139.14,348.746 C139.955,348.896 140.252,348.393 140.252,347.961 C140.252,347.574 140.238,346.55 140.23,345.191 C135.699,346.175 134.743,343.007 134.743,343.007 C134.002,341.125 132.934,340.624 132.934,340.624 C131.455,339.614 133.046,339.634 133.046,339.634 C134.681,339.749 135.541,341.313 135.541,341.313 C136.994,343.802 139.354,343.083 140.282,342.666 C140.43,341.614 140.851,340.896 141.316,340.489 C137.699,340.078 133.896,338.68 133.896,332.438 C133.896,330.66 134.531,329.205 135.573,328.067 C135.405,327.655 134.846,325.998 135.733,323.756 C135.733,323.756 137.1,323.318 140.212,325.426 C141.511,325.064 142.905,324.884 144.29,324.877 C145.674,324.884 147.067,325.064 148.368,325.426 C151.478,323.318 152.843,323.756 152.843,323.756 C153.732,325.998 153.173,327.655 153.006,328.067 C154.05,329.205 154.68,330.66 154.68,332.438 C154.68,338.696 150.871,340.073 147.243,340.476 C147.827,340.979 148.348,341.973 148.348,343.492 C148.348,345.67 148.328,347.427 148.328,347.961 C148.328,348.397 148.622,348.904 149.448,348.745 C155.916,346.586 160.579,340.485 160.579,333.29 C160.579,324.293 153.285,317 144.288,317"
                  id="Fill-51"
                >
                </path>
              </g>
            </g>
          </svg>
        </a>
        <a title="Soren's Blog Feed" href="http://sorentwo.com/feed.atom">
          <svg
            width="24px"
            height="24px"
            viewBox="0 0 16 16"
            version="1.1"
            xmlns="http://www.w3.org/2000/svg"
            xmlns:xlink="http://www.w3.org/1999/xlink"
          >
            <g id="Page-1" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
              <g
                id="Rss"
                transform="translate(-8.000000, -8.000000)"
                fill="#FFFFFF"
                fill-rule="nonzero"
              >
                <path
                  d="M20.502,23.316 L23.316,23.316 C23.316,15.247 16.752,8.678 8.684,8.678 L8.684,11.485 C15.199,11.485 20.502,16.794 20.502,23.316 Z M10.632,23.321 C11.1484462,23.3228599 11.6444068,23.1191422 12.010435,22.7548024 C12.3764633,22.3904626 12.582472,21.8954493 12.583,21.379 C12.5590029,20.3195218 11.69325,19.473156 10.6335,19.473156 C9.57375003,19.473156 8.70799707,20.3195218 8.684,21.379 C8.684,22.454 9.557,23.321 10.632,23.321 L10.632,23.321 Z M15.527,23.317 L18.345,23.317 C18.345,17.988 14.01,13.653 8.683,13.653 L8.683,16.459 C10.51,16.459 12.228,17.173 13.521,18.468 C14.8105688,19.7514668 15.5329302,21.4975937 15.527,23.317 L15.527,23.317 Z"
                  id="Shape"
                >
                </path>
              </g>
            </g>
          </svg>
        </a>
        <a title="SorenOne's Github" href="https://github.com/sorenone">
          <svg
            width="24px"
            height="24px"
            viewBox="0 0 33 32"
            version="1.1"
            xmlns="http://www.w3.org/2000/svg"
            xmlns:xlink="http://www.w3.org/1999/xlink"
          >
            <g id="Page-1" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
              <g id="GitHub-Mark" transform="translate(-128.000000, -317.000000)" fill="#FFFFFE">
                <path
                  d="M144.288,317 C135.294,317 128,324.293 128,333.29 C128,340.487 132.667,346.592 139.14,348.746 C139.955,348.896 140.252,348.393 140.252,347.961 C140.252,347.574 140.238,346.55 140.23,345.191 C135.699,346.175 134.743,343.007 134.743,343.007 C134.002,341.125 132.934,340.624 132.934,340.624 C131.455,339.614 133.046,339.634 133.046,339.634 C134.681,339.749 135.541,341.313 135.541,341.313 C136.994,343.802 139.354,343.083 140.282,342.666 C140.43,341.614 140.851,340.896 141.316,340.489 C137.699,340.078 133.896,338.68 133.896,332.438 C133.896,330.66 134.531,329.205 135.573,328.067 C135.405,327.655 134.846,325.998 135.733,323.756 C135.733,323.756 137.1,323.318 140.212,325.426 C141.511,325.064 142.905,324.884 144.29,324.877 C145.674,324.884 147.067,325.064 148.368,325.426 C151.478,323.318 152.843,323.756 152.843,323.756 C153.732,325.998 153.173,327.655 153.006,328.067 C154.05,329.205 154.68,330.66 154.68,332.438 C154.68,338.696 150.871,340.073 147.243,340.476 C147.827,340.979 148.348,341.973 148.348,343.492 C148.348,345.67 148.328,347.427 148.328,347.961 C148.328,348.397 148.622,348.904 149.448,348.745 C155.916,346.586 160.579,340.485 160.579,333.29 C160.579,324.293 153.285,317 144.288,317"
                  id="Fill-51"
                >
                </path>
              </g>
            </g>
          </svg>
        </a>
      </nav>
    </footer>
    """
  end
end
