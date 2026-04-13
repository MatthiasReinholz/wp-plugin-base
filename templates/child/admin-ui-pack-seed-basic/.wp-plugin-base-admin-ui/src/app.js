import { createElement, useEffect, useState } from "@wordpress/element";
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
  TextControl,
} from "@wordpress/components";
import { fetchOperation, getAdminUiConfig } from "../shared/api-client";

const SETTINGS_READ_OPERATION = "settings.read";
const SETTINGS_UPDATE_OPERATION = "settings.update";
const EXAMPLE_ITEMS_LIST_OPERATION = "example-items.list";

function SettingsForm({ isLoading, isSaving, message, onChangeMessage, onSave }) {
  if (isLoading) {
    return createElement(Spinner);
  }

  return createElement(
    "form",
    { onSubmit: onSave },
    createElement(
      Panel,
      null,
      createElement(PanelBody, {
        opened: true,
        title: __("Managed REST-backed form", "__PLUGIN_SLUG__"),
      }, createElement(TextControl, {
        label: __("Message", "__PLUGIN_SLUG__"),
        value: message,
        onChange: onChangeMessage,
        help: __("This form saves through the managed REST operations pack.", "__PLUGIN_SLUG__"),
      }))
    ),
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

function ExampleItems({ isLoading, items, selectedItem, onSelectItem }) {
  if (isLoading) {
    return createElement(Spinner);
  }

  return createElement(
    Flex,
    { align: "flex-start", gap: 6 },
    createElement(
      FlexBlock,
      null,
      createElement("h2", null, __("Seeded list", "__PLUGIN_SLUG__")),
      items.map((item) =>
        createElement(
          Button,
          {
            key: item.id,
            variant: item.id === selectedItem?.id ? "primary" : "secondary",
            onClick: () => onSelectItem(item.id),
            style: { marginRight: "8px", marginBottom: "8px" },
          },
          item.name
        )
      )
    ),
    createElement(
      FlexBlock,
      null,
      createElement("h2", null, __("Selected record", "__PLUGIN_SLUG__")),
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
  const selectedItem =
    items.find((item) => item.id === selectedItemIds[0]) || items[0] || null;

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
      createElement("h1", null, adminUiConfig.pluginName || "__PLUGIN_NAME__")
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
          selectedItem,
          onSelectItem: (itemId) => setSelectedItemIds(itemId ? [itemId] : []),
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
