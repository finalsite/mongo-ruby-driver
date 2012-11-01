$:.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require './test/replica_sets/rs_test_helper'

class ReplicaSetCountTest < Test::Unit::TestCase

  def setup
    ensure_rs
    @client = ReplSetClient.new(build_seeds(3), :read => :primary_preferred)
    assert @client.primary_pool
    @primary = Client.new(@client.primary_pool.host, @client.primary_pool.port)
    @db = @client.db(MONGO_TEST_DB)
    @db.drop_collection("test-sets")
    @coll = @db.collection("test-sets")
  end

  def teardown
    @rs.restart_killed_nodes
    @client.close if @conn
  end

  def test_correct_count_after_insertion_reconnect
    @coll.insert({:a => 20}, :safe => {:w => 2, :wtimeout => 10000})
    assert_equal 1, @coll.count

    # Kill the current master node
    @node = @rs.kill_primary

    rescue_connection_failure do
      @coll.insert({:a => 30}, :safe => true)
    end

    @coll.insert({:a => 40}, :safe => true)
    assert_equal 3, @coll.count, "Second count failed"
  end

  def test_count_command_sent_to_primary
    @coll.insert({:a => 20}, :safe => {:w => 2, :wtimeout => 10000})
    count_before = @primary['admin'].command({:serverStatus => 1})['opcounters']['command']
    assert_equal 1, @coll.count
    count_after = @primary['admin'].command({:serverStatus => 1})['opcounters']['command']
    assert_equal 2, count_after - count_before
  end
end
