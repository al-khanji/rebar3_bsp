%%%-------------------------------------------------------------------
%% @doc sample public API
%% @end
%%%-------------------------------------------------------------------

-module(sample_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    sample_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
