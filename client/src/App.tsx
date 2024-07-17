import { type Component, createSignal, For } from "solid-js";

import BatchAssign from "./BatchAssign";
import BatchListing from "./BatchListing";
import { Dynamic } from "solid-js/web";
import "flowbite";

const apps = [
  { name: "Batch Assign", component: BatchAssign },
  { name: "Batch Listing", component: BatchListing },
];
const [currentApp, setCurrentApp] = createSignal(0);

const App: Component = () => {
  return (
    <>
      <nav class="bg-gray-800 p-4 flex items-center space-x-2 justify-between items-center">
        <div class="flex items-center space-x-2">
          <For each={apps}>
            {(app, i) => (
              <button
                class="bg-gradient-to-r from-cyan-500 to-blue-500 transition ease-in-out duration-300 hover:from-indigo-500 hover:via-purple-500 hover:to-pink-500 text-white font-bold py-2 px-4 rounded-full ring-white ring-offset-2"
                classList={{ ring: i() === currentApp() }}
                onClick={() => setCurrentApp(i)}
              >
                {app.name}
              </button>
            )}
          </For>
        </div>
      </nav>
      <main class="h-4/5 m-4 flex flex-col grow justify-around place-items-center">
        <Dynamic component={apps[currentApp()].component} />
      </main>
      <footer class="bg-gray-800 px-2 py-1 flex shrink-0 justify-between font-semibold tracking-wide select-none">
        <p class="text-white">
          &copy; {new Date().getFullYear()} by High Steel Structures LLC
        </p>
        <p class="text-white/50 text-xs place-self-center">
          made with <span class="text-red-500">&hearts;</span> by Patrick Miller
        </p>
      </footer>
    </>
  );
};

export default App;
