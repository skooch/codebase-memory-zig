<script>
  import { onMount } from "svelte";
  import { loadProfile } from "./profile";

  let profile = null;

  onMount(async () => {
    profile = await loadProfile();
  });
</script>

<main>
  <h1>{profile?.name}</h1>
</main>
