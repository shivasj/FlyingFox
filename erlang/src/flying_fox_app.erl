-module(flying_fox_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    flying_fox_sup:start_link().

start() ->
    io:fwrite("here"),
    application:start(flying_fox).
%flying_fox_sup:start_link().

stop(_State) ->
    ok.