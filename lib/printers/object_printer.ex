defmodule JS2E.Printers.ObjectPrinter do
  @moduledoc """
  A printer for printing an 'object' type decoder.
  """

  require Logger
  alias JS2E.{Printer, Types}
  alias JS2E.Printers.Util
  alias JS2E.Types.ObjectType

  @spec print_type(
    Types.typeDefinition,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  def print_type(%ObjectType{name: name,
                             path: _path,
                             properties: properties,
                             required: required}, type_dict, schema_dict) do

    indent = Util.indent

    type_name = if name == "#" do
      "Root"
    else
      Util.upcase_first name
    end

    fields = print_fields(properties, required, type_dict, schema_dict)

    """
    type alias #{type_name} =
    #{indent}{#{fields}
    #{indent}}
    """
  end

  @spec print_fields(
    Types.propertyDictionary,
    [String.t],
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  defp print_fields(properties, required, type_dict, schema_dict) do
    indent = Util.indent

    properties
    |> Enum.map(&(print_type_property(&1, required, type_dict, schema_dict)))
    |> Enum.join("\n#{indent},")
  end

  @spec print_type_property(
    {String.t, String.t},
    [String.t],
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  defp print_type_property({property_name, property_path},
    required, type_dict, schema_dict) do

    field_name =
      property_path
      |> Printer.resolve_type(type_dict, schema_dict)
      |> print_field_name

    if property_name in required do
      " #{property_name} : #{field_name}"
    else
      " #{property_name} : Maybe #{field_name}"
    end
  end

  @spec print_field_name(Types.typeDefinition) :: String.t
  defp print_field_name(property_type) do

    if primitive_type?(property_type) do
      property_type_value = property_type.type

      case property_type_value do
        "integer" ->
          "Int"

        "number" ->
          "Float"

        _ ->
          Util.upcase_first property_type_value
      end

    else

      property_type_name = property_type.name
      if property_type_name == "#" do
        "Root"
      else
        Util.upcase_first property_type_name
      end

    end
  end

  @spec print_decoder(
    Types.typeDefinition,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  def print_decoder(%ObjectType{name: name,
                                path: _path,
                                properties: properties,
                                required: required},
    type_dict, schema_dict) do

    indent = Util.indent

    decoder_name = if name == "#" do
      "root"
    else
      Util.downcase_first name
    end

    type_name = if name == "#" do
      "Root"
    else
      Util.upcase_first name
    end

    decoder_properties = print_decoder_properties(
      properties, required, type_dict, schema_dict)

    """
    #{decoder_name}Decoder : Decoder #{type_name}
    #{decoder_name}Decoder =
    #{indent}decode #{type_name}
    #{decoder_properties}
    """
  end

  @spec print_decoder_properties(
    Types.propertyDictionary,
    [String.t],
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  defp print_decoder_properties(properties, required, type_dict, schema_dict) do

    properties
    |> Enum.map_join("\n", fn property_name ->
      print_decoder_property(property_name, required, type_dict, schema_dict)
    end)
  end

  @spec print_decoder_property(
    {String.t, String.t},
    [String.t],
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  defp print_decoder_property({property_name, property_path},
    required, type_dict, schema_dict) do

    property_type =
      property_path
      |> Printer.resolve_type(type_dict, schema_dict)

    decoder_name = print_decoder_name(property_type)

    is_required = property_name in required

    cond do
      union_type?(property_type) || one_of_type?(property_type) ->
        print_union_clause(property_name, decoder_name, is_required)

      enum_type?(property_type) ->
        property_type_decoder =
          property_type.type
          |> determine_primitive_type_decoder()

        print_enum_clause(property_name, property_type_decoder,
          decoder_name, is_required)

      true ->
        print_normal_clause(property_name, decoder_name, is_required)
    end
  end

  @spec determine_primitive_type_decoder(String.t) :: String.t
  defp determine_primitive_type_decoder(property_type_value) do
    case property_type_value do
      "integer" ->
        "int"

      "number" ->
        "float"

      _ ->
        property_type_value
    end
  end

  @spec print_decoder_name(Types.typeDefinition) :: String.t
  defp print_decoder_name(property_type) do

    if primitive_type?(property_type) do
      determine_primitive_type_decoder(property_type.type)
    else

      property_type_name = property_type.name
      if property_type_name == "#" do
        "rootDecoder"
      else
        "#{property_type_name}Decoder"
      end

    end
  end

  defp primitive_type?(type) do
    Util.get_string_name(type) == "PrimitiveType"
  end

  defp enum_type?(type) do
    Util.get_string_name(type) == "EnumType"
  end

  defp one_of_type?(type) do
    Util.get_string_name(type) == "OneOfType"
  end

  defp union_type?(type) do
    Util.get_string_name(type) == "UnionType"
  end

  defp print_union_clause(property_name, decoder_name, is_required) do
    double_indent = Util.indent(2)

    if is_required do
      "#{double_indent}|> " <>
        "required \"#{property_name}\" #{decoder_name}"

    else
      "#{double_indent}|> " <>
        "optional \"#{property_name}\" (nullable #{decoder_name}) Nothing"
    end
  end

  defp print_enum_clause(
    property_name,
    property_type_decoder,
    decoder_name,
    is_required) do

    double_indent = Util.indent(2)

    if is_required do
      "#{double_indent}|> " <>
        "required \"#{property_name}\" (#{property_type_decoder} |> " <>
        "andThen #{decoder_name})"

    else
      "#{double_indent}|> " <>
        "optional \"#{property_name}\" (#{property_type_decoder} |> " <>
        "andThen #{decoder_name} |> maybe) Nothing"
    end
  end

  defp print_normal_clause(property_name, decoder_name, is_required) do
    double_indent = Util.indent(2)

    if is_required do
      "#{double_indent}|> " <>
        "required \"#{property_name}\" #{decoder_name}"

    else
      "#{double_indent}|> " <>
        "optional \"#{property_name}\" (nullable #{decoder_name}) Nothing"
    end
  end

end
