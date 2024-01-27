FROM hexpm/elixir:1.16.0-erlang-26.2.1-alpine-3.17.5 as build

WORKDIR /app

ENV MIX_ENV=prod

# Dependencies

RUN mix local.hex --force && mix local.rebar --force

# Mix/Hex Dependencies

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

RUN mkdir config
COPY config/config.exs config/prod.exs config/

RUN mix deps.compile

# Compilation & Assets

COPY assets assets
COPY lib lib
COPY priv priv
RUN mix do compile, assets.deploy

# Changes to runtime don't require recompiling any code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# Released

FROM alpine:3.17.5 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/soren ./

ENV HOME=/app
ENV MIX_ENV=prod

ENTRYPOINT ["bin/soren"]
CMD ["start"]
