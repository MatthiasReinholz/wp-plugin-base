import "@wordpress/dataviews/build-style/style.css";

import { createElement, useEffect, useMemo, useState } from "@wordpress/element";
import { __ } from "@wordpress/i18n";
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Flex,
  FlexBlock,
  Notice,
  Panel,
  PanelBody,
  Spinner,
} from "@wordpress/components";
import { DataForm, DataViews } from "@wordpress/dataviews";
import { fetchOperation, getAdminUiConfig } from "../shared/api-client";

const SETTINGS_READ_OPERATION = "settings.read";
const SETTINGS_UPDATE_OPERATION = "settings.update";
const EXAMPLE_ITEMS_LIST_OPERATION = "example-items.list";
const DEFAULT_ITEMS_VIEW = {
  type: "table",
  fields: ["name", "description", "status"],
  search: "",
  page: 1,
  perPage: 10,
  sort: {
    field: "name",
    direction: "asc",
  },
};

function getSettingsFormConfig() {
  return {
    layout: {
      type: "regular",
    },
    fields: ["message"],
  };
}

function getSettingsFields() {
  return [
    {
      id: "message",
      label: __("Message", "__PLUGIN_SLUG__"),
      type: "text",
      Edit: "text",
      placeholder: __("Enter a message for the admin welcome panel.", "__PLUGIN_SLUG__"),
      description: __("This value is stored through the managed REST operations pack.", "__PLUGIN_SLUG__"),
      isValid: {
        required: true,
        minLength: 1,
      },
      getValue: ({ item }) => item.message || "",
      setValue: ({ value }) => ({ message: value }),
    },
  ];
}

function getExampleItemsFields() {
  return [
    {
      id: "name",
      label: __("Name", "__PLUGIN_SLUG__"),
      type: "text",
      enableGlobalSearch: true,
      filterBy: {
        isPrimary: true,
      },
      getValue: ({ item }) => item.name,
    },
    {
      id: "description",
      label: __("Description", "__PLUGIN_SLUG__"),
      type: "text",
      getValue: ({ item }) => item.description,
    },
    {
      id: "status",
      label: __("Status", "__PLUGIN_SLUG__"),
      type: "text",
      elements: [
        { value: "stable", label: __("stable", "__PLUGIN_SLUG__") },
        { value: "enabled", label: __("enabled", "__PLUGIN_SLUG__") },
        { value: "disabled", label: __("disabled", "__PLUGIN_SLUG__") },
      ],
      filterBy: {},
      getValue: ({ item }) => item.status,
    },
  ];
}

function SettingsForm({ isLoading, isSaving, message, onChangeMessage, onSave }) {
  const settingsFields = useMemo(() => getSettingsFields(), []);

  if (isLoading) {
    return createElement(Spinner);
  }

  return createElement(
    "form",
    { onSubmit: onSave },
    createElement(DataForm, {
      data: { message },
      fields: settingsFields,
      form: getSettingsFormConfig(),
      onChange: (value) => {
        onChangeMessage(value.message || "");
      },
    }),
    createElement(
      Flex,
      { justify: "flex-start", gap: 3 },
      createElement(
        Button,
        { variant: "primary", type: "submit", isBusy: isSaving },
        __("Save", "__PLUGIN_SLUG__")
      )
    )
  );
}

function ExampleItems({ isLoading, items, selection, onChangeSelection, onClickItem }) {
  const itemsFields = useMemo(() => getExampleItemsFields(), []);
  const [view, setView] = useState(DEFAULT_ITEMS_VIEW);
  const selectedIds = selection.length > 0 ? selection : items[0] ? [items[0].id] : [];
  const selectedItem = items.find((item) => item.id === selectedIds[0]) || null;
  const paginationInfo = {
    totalItems: items.length,
    totalPages: Math.max(1, Math.ceil(items.length / (view.perPage || DEFAULT_ITEMS_VIEW.perPage))),
  };

  return createElement(
    Flex,
    { direction: "column", gap: 4 },
    createElement(DataViews, {
      fields: itemsFields,
      data: items,
      view,
      onChangeView: setView,
      paginationInfo,
      isLoading,
      defaultLayouts: {
        table: {},
        list: {},
      },
      selection: selectedIds,
      onChangeSelection,
      onClickItem,
      search: true,
      searchLabel: __("Search example items", "__PLUGIN_SLUG__"),
      empty: createElement("p", null, __("No example items are available.", "__PLUGIN_SLUG__")),
      header: createElement(
        "p",
        null,
        __("This seeded starter demonstrates a DataViews-driven list/detail workflow over the managed REST operations pack.", "__PLUGIN_SLUG__")
      ),
    }),
    createElement(
      Card,
      null,
      createElement(
        CardHeader,
        null,
        createElement("strong", null, __("Selected record", "__PLUGIN_SLUG__"))
      ),
      createElement(
        CardBody,
        null,
        selectedItem
          ? createElement(
              Panel,
              null,
              createElement(PanelBody, {
                opened: true,
                title: selectedItem.name,
              }, createElement("p", null, selectedItem.description), createElement("p", null, __("Status:", "__PLUGIN_SLUG__"), " ", selectedItem.status))
            )
          : createElement("p", null, __("No example item selected.", "__PLUGIN_SLUG__"))
      )
    )
  );
}

export default function App() {
  const adminUiConfig = getAdminUiConfig();
  const [message, setMessage] = useState("");
  const [savedMessage, setSavedMessage] = useState("");
  const [items, setItems] = useState([]);
  const [selectedItemIds, setSelectedItemIds] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let isMounted = true;

    async function loadSettings() {
      try {
        const [settingsResponse, itemsResponse] = await Promise.all([
          fetchOperation(SETTINGS_READ_OPERATION),
          fetchOperation(EXAMPLE_ITEMS_LIST_OPERATION),
        ]);

        if (!isMounted) {
          return;
        }

        const nextItems = Array.isArray(itemsResponse.items) ? itemsResponse.items : [];

        setMessage(settingsResponse.message || "");
        setSavedMessage(settingsResponse.message || "");
        setItems(nextItems);
        setSelectedItemIds(nextItems[0] ? [nextItems[0].id] : []);
      } catch (requestError) {
        if (!isMounted) {
          return;
        }

        setError(requestError.message || __("Failed to load settings.", "__PLUGIN_SLUG__"));
      } finally {
        if (isMounted) {
          setIsLoading(false);
        }
      }
    }

    loadSettings();

    return () => {
      isMounted = false;
    };
  }, []);

  async function handleSave(event) {
    event.preventDefault();
    setIsSaving(true);
    setError("");

    try {
      const response = await fetchOperation(SETTINGS_UPDATE_OPERATION, {
        method: "POST",
        data: { message },
      });

      setSavedMessage(response.message || "");
    } catch (requestError) {
      setError(requestError.message || __("Failed to save settings.", "__PLUGIN_SLUG__"));
    } finally {
      setIsSaving(false);
    }
  }

  return createElement(
    Flex,
    { direction: "column", gap: 4 },
    createElement(
      FlexBlock,
      null,
      createElement("h1", null, adminUiConfig.pluginName || "__PLUGIN_NAME__"),
      createElement(
        "p",
        null,
        __("DataViews/DataForm starter mode is enabled for this scaffold.", "__PLUGIN_SLUG__")
      )
    ),
    error
      ? createElement(Notice, { status: "error", isDismissible: false }, error)
      : null,
    createElement(
      Card,
      null,
      createElement(
        CardHeader,
        null,
        createElement("strong", null, __("Settings Example", "__PLUGIN_SLUG__"))
      ),
      createElement(
        CardBody,
        null,
        createElement(SettingsForm, {
          isLoading,
          isSaving,
          message,
          onChangeMessage: setMessage,
          onSave: handleSave,
        })
      )
    ),
    createElement(
      Card,
      null,
      createElement(
        CardHeader,
        null,
        createElement("strong", null, __("Operation Catalog Example", "__PLUGIN_SLUG__"))
      ),
      createElement(
        CardBody,
        null,
        createElement(ExampleItems, {
          isLoading,
          items,
          selection: selectedItemIds,
          onChangeSelection: setSelectedItemIds,
          onClickItem: (item) => setSelectedItemIds(item ? [item.id] : []),
        })
      )
    ),
    createElement(
      Card,
      null,
      createElement(
        CardHeader,
        null,
        createElement("strong", null, __("Latest saved value", "__PLUGIN_SLUG__"))
      ),
      createElement(CardBody, null, createElement("p", null, savedMessage))
    )
  );
}
