# Copyright (C) 2009-2014 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'mongo/operation/write/write_command/writable'
require 'mongo/operation/write/write_command/delete'
require 'mongo/operation/write/write_command/insert'
require 'mongo/operation/write/write_command/update'

module Mongo

  module Operation

    module Write

      module WriteCommand

        # Write commands always go to primary servers.
        #
        # @return [ Mongo::ServerPreference::Primary ] A primary server preference.
        #
        # @since 3.0.0
        def server_preference
          Mongo::ServerPreference.get(:primary)
        end
      end
    end
  end
end

