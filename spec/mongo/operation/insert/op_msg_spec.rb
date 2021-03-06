require 'spec_helper'

describe Mongo::Operation::Insert::OpMsg do

  let(:documents) { [{ :_id => 1, :foo => 1 }] }
  let(:session) { nil }
  let(:spec) do
    { :documents     => documents,
      :db_name       => authorized_collection.database.name,
      :coll_name     => authorized_collection.name,
      :write_concern => write_concern,
      :ordered       => true,
      :session       => session
    }
  end

  let(:write_concern) do
    Mongo::WriteConcern.get(SpecConfig.instance.write_concern)
  end

  let(:op) { described_class.new(spec) }

  describe '#initialize' do

    context 'spec' do

      it 'sets the spec' do
        expect(op.spec).to eq(spec)
      end
    end
  end

  describe '#==' do

    context 'spec' do

      context 'when two ops have the same specs' do
        let(:other) { described_class.new(spec) }

        it 'returns true' do
          expect(op).to eq(other)
        end
      end

      context 'when two ops have different specs' do
        let(:other_documents) { [{ :bar => 1 }] }
        let(:other_spec) do
          { :documents     => other_documents,
            :db_name       => authorized_collection.database.name,
            :insert        => authorized_collection.name,
            :write_concern => write_concern.options,
            :ordered       => true
          }
        end
        let(:other) { described_class.new(other_spec) }

        it 'returns false' do
          expect(op).not_to eq(other)
        end
      end
    end
  end

  describe 'write concern' do

    context 'when write concern is not specified' do

      let(:spec) do
        { :documents     => documents,
          :db_name       => authorized_collection.database.name,
          :coll_name     => authorized_collection.name,
          :ordered       => true
        }
      end

      it 'does not include write concern in the selector' do
        expect(op.send(:command, authorized_primary)[:writeConcern]).to be_nil
      end
    end

    context 'when write concern is specified' do

      it 'includes write concern in the selector' do
        expect(op.send(:command, authorized_primary)[:writeConcern]).to eq(write_concern.options)
      end
    end
  end

  describe '#message' do

    context 'when the server supports OP_MSG' do
      min_server_version '3.6'

      let(:documents) do
        [ { foo: 1 }, { bar: 2 }]
      end

      let(:global_args) do
        {
            insert: TEST_COLL,
            ordered: true,
            writeConcern: write_concern.options,
            '$db' => SpecConfig.instance.test_db,
            lsid: session.session_id
        }
      end

      let!(:expected_payload_1) do
        {
            type: 1,
            payload: { identifier: 'documents',
                       sequence: op.documents
            }
        }
      end

      let(:session) do
        authorized_client.start_session
      end

      context 'when the topology is replica set or sharded' do
        min_server_version '3.6'
        require_topology :replica_set, :sharded

        let(:expected_global_args) do
          global_args.merge(Mongo::Operation::CLUSTER_TIME => authorized_client.cluster.cluster_time)
        end

        it 'creates the correct OP_MSG message' do
          authorized_client.command(ping:1)
          expect(Mongo::Protocol::Msg).to receive(:new).with([],
                                                             { validating_keys: true },
                                                             expected_global_args,
                                                             expected_payload_1)
          op.send(:message, authorized_primary)
        end
      end

      context 'when the topology is standalone', if: standalone? && sessions_enabled? do

        let(:expected_global_args) do
          global_args
        end

        it 'creates the correct OP_MSG message' do
          authorized_client.command(ping:1)
          expect(Mongo::Protocol::Msg).to receive(:new).with([],
                                                             { validating_keys: true },
                                                             expected_global_args,
                                                             expected_payload_1)
          op.send(:message, authorized_primary)
        end

        context 'when an implicit session is created and the topology is then updated and the server does not support sessions' do

          let(:expected_global_args) do
            global_args.dup.tap do |args|
              args.delete(:lsid)
            end
          end

          before do
            session.instance_variable_set(:@options, { implicit: true })
            # Topology is standalone, hence there is exactly one server
            authorized_client.cluster.servers.first.monitor.stop!(true)
            expect(authorized_primary.features).to receive(:sessions_enabled?).at_least(:once).and_return(false)
          end

          it 'creates the correct OP_MSG message' do
            authorized_client.command(ping:1)
            expect(expected_global_args).not_to have_key(:lsid)
            expect(Mongo::Protocol::Msg).to receive(:new).with([],
                                                               { validating_keys: true },
                                                               expected_global_args,
                                                               expected_payload_1)
            op.send(:message, authorized_primary)
          end
        end
      end

      context 'when the write concern is 0' do

        let(:write_concern) do
          Mongo::WriteConcern.get(w: 0)
        end

        context 'when the session is implicit' do

          let(:session) do
            # Use client#get_session so the session is implicit
            authorized_client.send(:get_session)
          end

          context 'when the topology is replica set or sharded' do
            min_server_version '3.6'
            require_topology :replica_set, :sharded

            let(:expected_global_args) do
              global_args.dup.tap do |args|
                args.delete(:lsid)
                args.merge!(Mongo::Operation::CLUSTER_TIME => authorized_client.cluster.cluster_time)
              end
            end

            it 'does not send a session id in the command' do
              authorized_client.command(ping:1)
              expect(Mongo::Protocol::Msg).to receive(:new).with([:more_to_come],
                                                                 { validating_keys: true },
                                                                 expected_global_args,
                                                                 expected_payload_1)
              op.send(:message, authorized_primary)
            end
          end

          context 'when the topology is standalone', if: standalone? && sessions_enabled? do

            let(:expected_global_args) do
              global_args.dup.tap do |args|
                args.delete(:lsid)
              end
            end

            it 'creates the correct OP_MSG message' do
              authorized_client.command(ping:1)
              expect(Mongo::Protocol::Msg).to receive(:new).with([:more_to_come],
                                                                 { validating_keys: true },
                                                                 expected_global_args,
                                                                 expected_payload_1)
              op.send(:message, authorized_primary)
            end
          end
        end

        context 'when the session is explicit' do
          min_server_version '3.6'
          require_topology :replica_set, :sharded

          let(:session) do
            authorized_client.start_session
          end

          let(:expected_global_args) do
            global_args.dup.tap do |args|
              args.delete(:lsid)
              args.merge!(Mongo::Operation::CLUSTER_TIME => authorized_client.cluster.cluster_time)
            end
          end

          it 'does not send a session id in the command' do
            authorized_client.command(ping:1)
            expect(Mongo::Protocol::Msg).to receive(:new).with([:more_to_come],
                                                               { validating_keys: true },
                                                               expected_global_args,
                                                               expected_payload_1)
            op.send(:message, authorized_primary)
          end
        end
      end
    end
  end
end
