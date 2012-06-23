#
#--
# ripfix (IPFIX for Ruby) (c) 2011 Brian Trammell
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines classes for implementing RFC5610
#

require_relative 'message'

class IETypeOptionsTemplate < OptionsTemplate
  
  def initialize(model, tid)
    super(model, tid)
    add_scope "informationElementId"
    add_scope "privateEnterpiseNumber"
    << "informationElementDataType"
    << "informationElementName"
  end

  def self.is_type_options_record(h)
    h[:informationElementId] && h[:privateEnterpriseNumber] && h[:informationElementDataType]
  end

end

class InfoModel
  def add_type_options_record(h)
    if (IETypeOptionsTemplate.is_type_options_record(h))
      add(InfoElement.new(h[:informationElementName],
                          h[:privateEnterpriseNumber], 
                          h[:informationElementId],
                   @types[h[:informationElementDataType]]))
    end
  end
end

class InfoElement
  def type_options_record
    h = Hash.new
    h[:informationElementId] = number
    h[:privateEnterpriseNumber] = pen
    h[:informationElementDataType] = type.number
    h[:informationElementName] = name
  end
end