import { AppRegistry } from "react-native";
import App from "./App";

// react native entry point; react-native-web mounts it into the dom
AppRegistry.registerComponent("GEMStone", () => App);
// on web the root tag is a dom element (rn types only know native tags)
AppRegistry.runApplication("GEMStone", { rootTag: document.getElementById("root") as never, initialProps: {} });
