defmodule TenantStarter do
  use Agent

  def start_link(_opts) do
    customers = [
      [1_000 * 100, "Jonathan"],
      [800 * 100, "Joseph"],
      [10_000 * 100, "Jotaro"],
      [100_000 * 100, "Josuke"],
      [5_000 * 100, "Giorno"]
    ]
    for {[limit, name], index} <- Enum.with_index(customers) do
      # do_insert_customer(conn, name, limit)
      TenantSupervisor.create_customer(index + 1, name, limit)
    end
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end
end

defmodule TenantMapper do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def value do
    Agent.get(__MODULE__, & &1)
  end

  def add_tenant(id, pid) do
    Agent.update(__MODULE__, &Map.put_new(&1, id, pid))
  end

  def get_tenant(id) do
    Agent.get(__MODULE__, &Map.get(&1, id))
  end
end

defmodule TenantSupervisor do
  use DynamicSupervisor

  def create_customer(customer_id, name, limit) do
    {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, %{
      id: String.to_atom("customer_tenant_#{customer_id}"),
      start: {SqliteServer, :start_link, [customer_id, name, limit]}
    })
    TenantMapper.add_tenant(customer_id, pid)
    :ok
  end

  # Private API

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

defmodule SqliteServer do
  use GenServer

  # def init_db do
  #   GenServer.call(__MODULE__, :init_db)
  # end

  def insert_customer(name, limit) do
    GenServer.call(__MODULE__, {:insert_customer, {name, limit}})
  end

  def insert_transaction(customer_id, description, type, value) do
    if pid = TenantMapper.get_tenant(customer_id) do
      GenServer.call(pid, {:insert_transaction, {customer_id, description, type, value}})
    else
      :ok
    end
  end

  # Private API
  def start_link(customer_id, name, limit) do
    GenServer.start_link(__MODULE__, [customer_id, name, limit])
    # GenServer.start_link(__MODULE__, [])
  end

  def init([customer_id, name, limit]) do
    path = "#{System.get_env("DATABASE_PATH")}/#{customer_id}.db"
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    do_init_db(conn)
    do_insert_customer(conn, name, limit)
    {:ok, insert_transaction_stmt} = Exqlite.Sqlite3.prepare(conn, "insert into transactions (customer_id, description, \"type\", \"value\") values (?1, ?2, ?3, ?4)")
    {:ok, %{conn: conn, insert_transaction_stmt: insert_transaction_stmt}}
  end

  def handle_call({:insert_customer, {name, limit}}, _from, %{conn: conn} = state) do
    :ok = do_insert_customer(conn, name, limit)
    {:reply, :ok, state}
  end

  def handle_call({:insert_transaction, {customer_id, description, type, value}}, _from, %{conn: conn, insert_transaction_stmt: statement} = state) do
    # {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "insert into transactions (customer_id, description, \"type\", \"value\") values (?1, ?2, ?3, ?4)")
    :ok = Exqlite.Sqlite3.bind(conn, statement, [customer_id, description, type, value])
    Exqlite.Sqlite3.step(conn, statement)
    # :ok = Exqlite.Sqlite3.release(conn, statement)
    {:reply, :ok, state}
  rescue
    RuntimeError ->
      {:reply, :ok, state}
  end

  # def handle_call(:init_db, _from, %{conn: conn} = state) do
  #   do_init_db(conn)
  #   {:reply, :ok, state}
  # end

  defp do_init_db(conn) do
    :ok = Exqlite.Sqlite3.execute(conn, "create table customers (id integer primary key, name text, \"limit\" integer, balance integer not null)")
    :ok = Exqlite.Sqlite3.execute(conn, "create table transactions (id integer primary key, description text, customer_id integer, type text, value integer, foreign key (customer_id) references customers(id))")
    # :ok = Exqlite.Sqlite3.execute(conn, "create index transactions_customer_id ON transactions(customer_id)")
    :ok = Exqlite.Sqlite3.execute(conn, """
    CREATE TRIGGER validate_balance_before_insert_transaction
    BEFORE INSERT ON transactions
    BEGIN
      SELECT CASE WHEN (select balance from customers where id = NEW.customer_id) + (
        case when NEW.type = 'c' then +NEW.value else -NEW.value end
      ) < -(select "limit" from customers where id = NEW.customer_id) THEN
        RAISE (ABORT, 'Invalid value')
      END;

      UPDATE customers
      SET balance = customers.balance + (case when NEW.type = 'c' then +NEW.value else -NEW.value end)
      WHERE id = NEW.customer_id;
    END;
    """)
    # customers = [
    #   [1_000 * 100, "Jonathan"],
    #   [800 * 100, "Joseph"],
    #   [10_000 * 100, "Jotaro"],
    #   [100_000 * 100, "Josuke"],
    #   [5_000 * 100, "Giorno"]
    # ]
    # for [limit, name] <- customers do
    #   do_insert_customer(conn, name, limit)
    # end

    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA synchronous = OFF")
    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode = MEMORY")
    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA foreign_keys = ON")
  end

  defp do_insert_customer(conn, name, limit) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "insert into customers (\"limit\", name, balance) values (?1, ?2, 0)")
    :ok = Exqlite.Sqlite3.bind(conn, statement, [limit, name])
    :done = Exqlite.Sqlite3.step(conn, statement)
    :ok = Exqlite.Sqlite3.release(conn, statement)
    :ok
  end
end
