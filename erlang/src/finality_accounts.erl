%depending on how complicated it is to compute the next top, we may have to charge an additional fee when people delete in bad spots.


%The byte array should be backed up to disk. Instead of writing the entire thing to disk at each block, we should manipulate individual bits in the file at each block. 
%If the bit is set to zero, then that address is ready to be written in.
%Top should point to the lowest known address that is deleted.
-module(finality_accounts).
-behaviour(gen_server).
-export([start_link/0,code_change/3,handle_call/3,handle_cast/2,handle_info/2,init/1,terminate/2, read_account/1,write/2,test/0,size/0,write_helper/3,top/0,delete/1]).
-define(file, "accounts.db").
-define(empty, "d_accounts.db").
%-define(zeros, << 0:103 >>).
-define(zeros, #acc{balance = 0, nonce = 0, pub = 0}).
%Pub is 65 bytes. balance is 48 bits. Nonce is 32 bits. bringing the total to 75 bytes.
-define(word, 75).
-record(acc, {balance = 0, nonce = 0, pub = ""}).
write_helper(N, Val, File) ->
%since we are reading it a bunch of changes at a time for each block, there should be a way to only open the file once, make all the changes, and then close it. 
    case file:open(File, [write, read, raw]) of
        {ok, F} ->
            file:pwrite(F, N*?word, Val),
            file:close(F);
        {error, _Reason} ->
            write_helper(N, Val, File)
    end.
init(ok) -> 
    case file:read_file(?empty) of
        {error, enoent} -> 
            P = base64:decode(constants:master_pub()),
            Balance = constants:initial_coins(),
            write_helper(0, <<Balance:48, 0:32, P/binary>>, ?file),
            Top = 1,
            DeletedArray = << 1:1 , 0:7 >>,
            write_helper(0, DeletedArray, ?empty);
        {ok, DeletedArray} ->
            Top = walk(0, DeletedArray)
    end,
    {ok, {Top, DeletedArray}}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, ok, []).
code_change(_OldVsn, State, _Extra) -> {ok, State}.
terminate(_, _) -> io:format("died!"), ok.
handle_info(_, X) -> {noreply, X}.
walk(Top, Array) -> 
    << _:Top, Tail/bitstring>> = Array,
    walk_helper(Tail, Top).
walk_helper(<<>>, Counter) -> Counter;
walk_helper(<< 127:8, B/bitstring>>, Counter) -> walk_helper(B, Counter + 8);
walk_helper(<< 1:1, B/bitstring>>, Counter) -> walk_helper(B, Counter + 1);
walk_helper(<< 0:1, _B/bitstring>>, Counter) -> Counter.
handle_cast({delete, N}, {Top, Array}) -> 
    Byte = hd(binary_to_list(read(N div 8, 1, ?empty))),
    Remove = bnot round(math:pow(2, N rem 8)),
    NewByte = Byte band Remove,
    write_helper(N div 8, <<NewByte>>, ?empty),
    <<A:N,_:1,B/bitstring>> = Array,
    NewArray = <<A:N,0:1,B/bitstring>>,
    write_helper(N, ?zeros, ?file),
    {noreply, {min(Top, N), NewArray}};
handle_cast({write, N, Val}, {Top, Array}) -> 
    S = size(),
    if
        N > S -> write_helper(N div 8, <<0>>, ?empty);
        true -> 0 = 0
    end,
    Byte = hd(binary_to_list(read(N div 8, 1, ?empty))),
    Remove = round(math:pow(2, N rem 8)),
    NewByte = Byte bor Remove,
    write_helper(N div 8, <<NewByte>>, ?empty),
    <<A:N,_:1,B/bitstring>> = Array,
    NewArray = <<A:N,1:1,B/bitstring>>,
    false = N > size(),
    write_helper(N, Val, ?file),
    {noreply, {walk(Top, NewArray), NewArray}}.
handle_call(top, _From, {Top, Array}) -> {reply, Top, {Top, Array}}.
top() -> gen_server:call(?MODULE, top).
delete(N) -> gen_server:cast(?MODULE, {delete, N}).
read(N, Bytes, F) -> 
    {ok, File} = file:open(F, [read, binary, raw]),
    {ok, X} = file:pread(File, N, Bytes),
    file:close(File),
    X.
read_account(N) -> %maybe this should be a call too, that way we can use the ram to see if it is already deleted?
    X = read(N*?word, ?word, ?file),
    <<Balance:48, Nonce:32, P/binary>> = X,
    Pub = base64:encode(P),
    #acc{balance = Balance, nonce = Nonce, pub = Pub}.
write(N, Acc) ->
    P = base64:decode(Acc#acc.pub),
    65 = size(P),
    Val = << (Acc#acc.balance):48, 
             (Acc#acc.nonce):32, 
             P/binary >>,
    gen_server:cast(?MODULE, {write, N, Val}).
size() -> filelib:file_size(?file) div ?word.
append(Acc) -> write(top(), Acc).
test() -> 
    << 13:4 >> = << 1:1, 1:1, 0:1, 1:1 >>,%13=8+4+1
    0 = walk(0, << >>),
    0 = walk(0, << 0:1 >>),
    2 = walk(0, << 1:1, 1:1, 0:1, 1:1 >>),
    3 = walk(0, << 1:1, 1:1, 1:1, 0:1, 0:30 >>),
    1 = walk(0, << 2:2 >>),
    0 = walk(0, << 1:2 >>),
    2 = walk(0, << 24:5 >>),
    5 = walk(0, << 31:5 >>),
    5 = walk(2, << 31:5 >>),
    5 = walk(5, << 31:5 >>),
    %accounts.db needs to be empty before starting node to run this test.
    Pub = <<"BIXotG1x5BhwxVKxjsCyrgJASovEJ5Yk/PszEdIoS/nKRNRv0P0E8RvNloMnBrFnggjV/F7pso/2PA4JDd6WQCE=">>,
    Balance = 50000000,
    A = #acc{pub = Pub, nonce = 0, balance = Balance},
    1 = top(),
    append(A),
    2 = top(),
    append(A),
    3 = top(),
    delete(0),
    0 = top(),
    append(A),
    3 = top(),
    delete(1),
    1 = top(),
    append(A),
    3 = top(),
    delete(1),
    delete(0),
    0 = top(),
    append(A),
    1 = top(),
    append(A),
    3 = top(),
    Acc = read_account(0),
    Pub = Acc#acc.pub,
    Balance = Acc#acc.balance,
    success.
