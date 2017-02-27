%%%-------------------------------------------------------------------
%%% @author Torben Hoffmann <torben.lehoff@gmail.com>
%%% @copyright (C) 2011, Torben Hoffmann
%%% @doc
%%%
%%% @end
%%% Created : 27 Jun 2011 by Torben Hoffmann <torben.lehoff@gmail.com>
%%%-------------------------------------------------------------------
-module(chronos).

-behaviour(gen_server).

%% API
-export([start_link/1,
         stop/1,
         start_timer/4,
         stop_timer/2
        ]).



%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-export_type([server_name/0,
              timer_name/0,
              timer_duration/0]).

-record(chronos_state,
        {running = []  :: [{timer_name(), reference()}]
        }).

%% Types
-type server_name()   :: atom().
%%-type server_ref()    :: server_name() | pid().
-type timer_name()    :: term().
-type function_name() :: atom().
-type args()          :: [term()].
-type callback()      :: {module(), function_name(), args()}.
-type timer_duration():: non_neg_integer().
-type state()         :: #chronos_state{}.



%%%===================================================================
%%% API
%%%===================================================================

-spec start_link(server_name()) -> {'ok', pid()} | 'ignore' | {'error', term()}.
start_link(ServerName) ->
    gen_server:start_link({local, ServerName}, ?MODULE, _Args = [], _Opts = []).

%% -start_link() -> {'ok',pid()} | 'ignore' | {'error',term()}.
%% start_link() ->
%%     gen_server:start_link(?MODULE, [], []).

-spec stop(server_name()) -> ok.
stop(ServerName) ->
    call(ServerName, stop).

-spec start_timer(server_name(), timer_name(), non_neg_integer(), callback()) ->
                         'ok' | {'error',term()}.
start_timer(ServerName, TimerName, Timeout, Callback) ->
    call(ServerName, {start_timer, TimerName, Timeout, Callback}).

-spec stop_timer(server_name(), timer_name()) -> { 'ok', non_neg_integer()}
                                               | 'not_running'
                                               | {'error',term()}.
stop_timer(ServerName, TimerName) ->
    call(ServerName, {stop_timer, TimerName}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================


-spec init([]) -> {'ok', state()} | {'stop', term()} | 'ignore'.
init(_Args) ->
    {ok, #chronos_state{}}.

-spec handle_call(term(), term(), state()) ->
    {'reply', 'ok' | {'error', term()} , state()}
  | {'stop', term(), 'ok', state()}.
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call({start_timer, Name, Time, Callback}, _From,
            #chronos_state{running=R}=State) ->
    %% If the Name timer is running we clean it up.
    R1 = case lists:keytake(Name, 1, R) of
             false ->
                 R;
             {value, {_, TRef}, Ra} ->
                 _ = erlang:cancel_timer(TRef),
                 Ra
         end,
    TRefNew = erlang:start_timer(Time, self(), {Name,Callback}),
    {reply, ok, State#chronos_state{running=[{Name,TRefNew}|R1]}};
handle_call({stop_timer, Name}, _From,
            #chronos_state{running=R}=State) ->
    case lists:keytake(Name, 1, R) of
        {value, {_, TRef}, Rnext} ->
            TimeLeft = erlang:cancel_timer(TRef),
            {reply, {ok, TimeLeft}, State#chronos_state{running=Rnext}};
        false ->
            {reply, not_running, State}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({timeout, TRef, {Timer, {M, F, Args}}}, #chronos_state{running=R}=State) ->
    NewR =
        case lists:keytake(Timer, 1, R) of
            {value, {_,TRef}, R1} ->
                spawn( fun() ->
                               erlang:apply(M, F, Args)
                       end ),
                R1;
            {value, _, R1} -> %% has to ignore since TRef is not the current one
                R1;
            false ->
                R
            end,
    {noreply, State#chronos_state{running=NewR}}.

terminate(_Reason, #chronos_state{running=R}) ->
    _ = [ erlang:cancel_timer(TRef)
      || {_, TRef} <- R ],
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
call(ServerName, Msg) ->
    gen_server:call(ServerName, Msg, 5000).
