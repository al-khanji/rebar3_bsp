%%==============================================================================
%% Macro Definitions
%%==============================================================================
-define(JSONRPC_VSN, <<"2.0">>).
-define(BSP_VSN, <<"2.0.0">>).

-define(SOURCE_ITEM_KIND_FILE, 1).
-define(SOURCE_ITEM_KIND_DIR, 2).

%%==============================================================================
%% Type Definitions
%%==============================================================================

%% Common
-type uri() :: binary().

%% build/initialize
-type buildClientCapabilities() :: #{ languageIds := [binary()] }.
-type initializeBuildParams() :: #{ displayName := binary()
                                  , version := binary()
                                  , bspVersion := binary()
                                  , rootUri := uri()
                                  , capabilities := buildClientCapabilities()
                                  , data => any()
                                  }.
-type compileProvider() :: #{ languageIds := [binary()] }.
-type testProvider() :: #{ languageIds := [binary()] }.
-type runProvider() :: #{ languageIds := [binary()] }.
-type buildServerCapabilities() :: #{ compileProvider => compileProvider()
                                    , testProvider => testProvider()
                                    , runProvider => runProvider()
                                    , inverseSourcesProvider => boolean()
                                    , dependencySourcesProvider => boolean()
                                    , resourcesProvider => boolean()
                                    , buildTargetChangedProvider => boolean()
                                    }.
-type initializeBuildResult() :: #{ displayName := binary()
                                  , version := binary()
                                  , bspVersion := binary()
                                  , capabilities := buildServerCapabilities()
                                  , data => any()
                                  }.

%% build/initialized
-type initializedBuildParams() :: #{}.

%% workspace/buildTargets
-type workspaceBuildTargetsParams() :: #{}.
-type buildTargetIdentifier() :: #{ uri := uri() }.
-type buildTargetCapabilities() :: #{ canCompile := boolean()
                                    , canTest := boolean()
                                    , canRun := boolean()
                                    }.
-type buildTarget() :: #{ id := buildTargetIdentifier()
                        , displayName => binary()
                        , baseDirectory => uri()
                        , tags => [binary()]
                        , capabilities := buildTargetCapabilities()
                        , languageIds := [binary()]
                        , dependencies := [buildTargetIdentifier()]
                        , dataKind => binary()
                        , data => any()
                        }.
-type workspaceBuildTargetsResult() :: #{ targets => [buildTarget()]}.

%% buildTarget/compile
-type compileParams() :: #{ targets := [buildTargetIdentifier()]
                          , originId => binary()
                          , arguments => [binary()]
                          }.
-type compileResult() :: #{ originId => binary()
                          , statusCode := integer()
                          , dataKind := binary()
                          , data => any()
                          }.

%% buildTarget/sources
-type buildTargetSourcesParams() :: #{ targets := [buildTargetIdentifier()] }.
-type sourceItemKind() :: ?SOURCE_ITEM_KIND_FILE
                        | ?SOURCE_ITEM_KIND_DIR.
-type sourceItem() :: #{ uri := uri()
                       , kind := sourceItemKind()
                       , generated := boolean()
                       }.
-type sourcesItem() :: #{ target := buildTargetIdentifier()
                        , sources := [sourceItem()]
                        , roots => [uri()]
                        }.
-type buildTargetSourcesResult() :: #{ items := [sourcesItem()] }.

%% buildTarget/dependencySources
-type dependencySourcesParams() :: #{ targets := [buildTargetIdentifier()] }.
-type dependencySourcesItem() :: #{ target := buildTargetIdentifier()
                                  , sources := [uri()]
                                  }.
-type dependencySourcesResult() :: #{ items := [dependencySourcesItem()] }.
