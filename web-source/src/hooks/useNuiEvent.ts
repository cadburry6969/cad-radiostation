import {MutableRefObject, useEffect, useRef} from "react";
import {noop} from "../utils/misc";

interface NuiMessageData<T = unknown> {
  action: string;
  data?: T;
  [key: string]: any;
}

type NuiHandlerSignature<T> = (data: T) => void;

// Subscribes to a single `action` sent by the client scripts via SendNUIMessage.

export const useNuiEvent = <T = any>(
  action: string,
  handler: (data: T) => void
) => {
  const savedHandler: MutableRefObject<NuiHandlerSignature<T>> = useRef(noop);

  // Make sure we handle for a reactive handler
  useEffect(() => {
    savedHandler.current = handler;
  }, [handler]);

  useEffect(() => {
    const eventListener = (event: MessageEvent<NuiMessageData<T>>) => {
      const { action: eventAction, data } = event.data;

      if (savedHandler.current) {
        if (eventAction === action) {
          // If data is undefined, it means the message is flat (original Lua format)
          // We pass the whole event.data minus the action property
          if (data === undefined) {
            const { action: _, ...rest } = event.data;
            savedHandler.current(rest as T);
          } else {
            savedHandler.current(data);
          }
        }
      }
    };

    window.addEventListener("message", eventListener);
    // Remove Event Listener on component cleanup
    return () => window.removeEventListener("message", eventListener);
  }, [action]);
};