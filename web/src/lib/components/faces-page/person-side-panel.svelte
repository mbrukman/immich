<script lang="ts">
  import Icon from '$lib/components/elements/icon.svelte';
  import LoadingSpinner from '$lib/components/shared-components/loading-spinner.svelte';
  import { timeBeforeShowLoadingSpinner } from '$lib/constants';
  import { assetViewingStore } from '$lib/stores/asset-viewing.store';
  import { photoViewerImgElement } from '$lib/stores/assets-store.svelte';
  import { boundingBoxesArray } from '$lib/stores/people.store';
  import { websocketEvents } from '$lib/stores/websocket';
  import { getPeopleThumbnailUrl, handlePromiseError } from '$lib/utils';
  import { handleError } from '$lib/utils/handle-error';
  import { zoomImageToBase64 } from '$lib/utils/people-utils';
  import { getPersonNameWithHiddenValue } from '$lib/utils/person';
  import {
    AssetTypeEnum,
    createPerson,
    deleteFace,
    getFaces,
    reassignFacesById,
    type AssetFaceResponseDto,
    type PersonResponseDto,
  } from '@immich/sdk';
  import { IconButton, modalManager } from '@immich/ui';
  import { mdiAccountOff, mdiArrowLeftThin, mdiPencil, mdiRestart, mdiTrashCan } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { linear } from 'svelte/easing';
  import { fly } from 'svelte/transition';
  import ImageThumbnail from '../assets/thumbnail/image-thumbnail.svelte';
  import { NotificationType, notificationController } from '../shared-components/notification/notification';
  import AssignFaceSidePanel from './assign-face-side-panel.svelte';

  interface Props {
    assetId: string;
    assetType: AssetTypeEnum;
    onClose: () => void;
    onRefresh: () => void;
  }

  let { assetId, assetType, onClose, onRefresh }: Props = $props();

  // keep track of the changes
  let peopleToCreate: string[] = [];
  let assetFaceGenerated: string[] = [];

  // faces
  let peopleWithFaces: AssetFaceResponseDto[] = $state([]);
  let selectedPersonToReassign: Record<string, PersonResponseDto> = $state({});
  let selectedPersonToCreate: Record<string, string> = $state({});
  let editedFace: AssetFaceResponseDto | undefined = $state();

  // loading spinners
  let isShowLoadingDone = $state(false);
  let isShowLoadingPeople = $state(false);

  // search people
  let showSelectedFaces = $state(false);

  // timers
  let loaderLoadingDoneTimeout: ReturnType<typeof setTimeout>;
  let automaticRefreshTimeout: ReturnType<typeof setTimeout>;

  const thumbnailWidth = '90px';

  async function loadPeople() {
    const timeout = setTimeout(() => (isShowLoadingPeople = true), timeBeforeShowLoadingSpinner);
    try {
      peopleWithFaces = await getFaces({ id: assetId });
    } catch (error) {
      handleError(error, $t('errors.cant_get_faces'));
    } finally {
      clearTimeout(timeout);
    }
    isShowLoadingPeople = false;
  }

  const onPersonThumbnail = (personId: string) => {
    assetFaceGenerated.push(personId);
    if (
      isEqual(assetFaceGenerated, peopleToCreate) &&
      loaderLoadingDoneTimeout &&
      automaticRefreshTimeout &&
      Object.keys(selectedPersonToCreate).length === peopleToCreate.length
    ) {
      clearTimeout(loaderLoadingDoneTimeout);
      clearTimeout(automaticRefreshTimeout);
      onRefresh();
    }
  };

  onMount(() => {
    handlePromiseError(loadPeople());
    return websocketEvents.on('on_person_thumbnail', onPersonThumbnail);
  });

  const isEqual = (a: string[], b: string[]): boolean => {
    return b.every((valueB) => a.includes(valueB));
  };

  const handleReset = (id: string) => {
    if (selectedPersonToReassign[id]) {
      delete selectedPersonToReassign[id];
    }
    if (selectedPersonToCreate[id]) {
      delete selectedPersonToCreate[id];
    }
  };

  const handleEditFaces = async () => {
    loaderLoadingDoneTimeout = setTimeout(() => (isShowLoadingDone = true), timeBeforeShowLoadingSpinner);
    const numberOfChanges = Object.keys(selectedPersonToCreate).length + Object.keys(selectedPersonToReassign).length;

    if (numberOfChanges > 0) {
      try {
        for (const personWithFace of peopleWithFaces) {
          const personId = selectedPersonToReassign[personWithFace.id]?.id;

          if (personId) {
            await reassignFacesById({
              id: personId,
              faceDto: { id: personWithFace.id },
            });
          } else if (selectedPersonToCreate[personWithFace.id]) {
            const data = await createPerson({ personCreateDto: {} });
            peopleToCreate.push(data.id);
            await reassignFacesById({
              id: data.id,
              faceDto: { id: personWithFace.id },
            });
          }
        }

        notificationController.show({
          message: $t('people_edits_count', { values: { count: numberOfChanges } }),
          type: NotificationType.Info,
        });
      } catch (error) {
        handleError(error, $t('errors.cant_apply_changes'));
      }
    }

    isShowLoadingDone = false;
    if (peopleToCreate.length === 0) {
      clearTimeout(loaderLoadingDoneTimeout);
      onRefresh();
    } else {
      automaticRefreshTimeout = setTimeout(onRefresh, 15_000);
    }
  };

  const handleCreatePerson = (newFeaturePhoto: string | null) => {
    if (newFeaturePhoto && editedFace) {
      selectedPersonToCreate[editedFace.id] = newFeaturePhoto;
    }
    showSelectedFaces = false;
  };

  const handleReassignFace = (person: PersonResponseDto | null) => {
    if (person && editedFace) {
      selectedPersonToReassign[editedFace.id] = person;
    }
    showSelectedFaces = false;
  };

  const handleFacePicker = (face: AssetFaceResponseDto) => {
    editedFace = face;
    showSelectedFaces = true;
  };

  const deleteAssetFace = async (face: AssetFaceResponseDto) => {
    try {
      if (!face.person) {
        return;
      }

      const isConfirmed = await modalManager.showDialog({
        prompt: $t('confirm_delete_face', { values: { name: face.person.name } }),
      });
      if (!isConfirmed) {
        return;
      }

      await deleteFace({ id: face.id, assetFaceDeleteDto: { force: false } });

      peopleWithFaces = peopleWithFaces.filter((f) => f.id !== face.id);

      await assetViewingStore.setAssetId(assetId);
    } catch (error) {
      handleError(error, $t('error_delete_face'));
    }
  };
</script>

<section
  transition:fly={{ x: 360, duration: 100, easing: linear }}
  class="absolute top-0 h-full w-[360px] overflow-x-hidden p-2 dark:text-immich-dark-fg bg-light"
>
  <div class="flex place-items-center justify-between gap-2">
    <div class="flex items-center gap-2">
      <IconButton
        shape="round"
        color="secondary"
        variant="ghost"
        icon={mdiArrowLeftThin}
        aria-label={$t('back')}
        onclick={onClose}
      />
      <p class="flex text-lg text-immich-fg dark:text-immich-dark-fg">{$t('edit_faces')}</p>
    </div>
    {#if !isShowLoadingDone}
      <button
        type="button"
        class="justify-self-end rounded-lg p-2 hover:bg-immich-dark-primary hover:dark:bg-immich-dark-primary/50"
        onclick={() => handleEditFaces()}
      >
        {$t('done')}
      </button>
    {:else}
      <LoadingSpinner />
    {/if}
  </div>

  <div class="px-4 py-4 text-sm">
    <div class="mt-4 flex flex-wrap gap-2">
      {#if isShowLoadingPeople}
        <div class="flex w-full justify-center">
          <LoadingSpinner />
        </div>
      {:else}
        {#each peopleWithFaces as face, index (face.id)}
          {@const personName = face.person ? face.person?.name : $t('face_unassigned')}
          <div class="relative h-[115px] w-[95px]">
            <div
              role="button"
              tabindex={index}
              class="absolute start-0 top-0 h-[90px] w-[90px] cursor-default"
              onfocus={() => ($boundingBoxesArray = [peopleWithFaces[index]])}
              onmouseover={() => ($boundingBoxesArray = [peopleWithFaces[index]])}
              onmouseleave={() => ($boundingBoxesArray = [])}
            >
              <div class="relative">
                {#if selectedPersonToCreate[face.id]}
                  <ImageThumbnail
                    curve
                    shadow
                    url={selectedPersonToCreate[face.id]}
                    altText={$t('new_person')}
                    title={$t('new_person')}
                    widthStyle={thumbnailWidth}
                    heightStyle={thumbnailWidth}
                  />
                {:else if selectedPersonToReassign[face.id]}
                  <ImageThumbnail
                    curve
                    shadow
                    url={getPeopleThumbnailUrl(selectedPersonToReassign[face.id])}
                    altText={selectedPersonToReassign[face.id].name}
                    title={$getPersonNameWithHiddenValue(
                      selectedPersonToReassign[face.id].name,
                      selectedPersonToReassign[face.id]?.isHidden,
                    )}
                    widthStyle={thumbnailWidth}
                    heightStyle={thumbnailWidth}
                    hidden={selectedPersonToReassign[face.id].isHidden}
                  />
                {:else if face.person}
                  <ImageThumbnail
                    curve
                    shadow
                    url={getPeopleThumbnailUrl(face.person)}
                    altText={face.person.name}
                    title={$getPersonNameWithHiddenValue(face.person.name, face.person.isHidden)}
                    widthStyle={thumbnailWidth}
                    heightStyle={thumbnailWidth}
                    hidden={face.person.isHidden}
                  />
                {:else}
                  {#await zoomImageToBase64(face, assetId, assetType, $photoViewerImgElement)}
                    <ImageThumbnail
                      curve
                      shadow
                      url="/src/lib/assets/no-thumbnail.png"
                      altText={$t('face_unassigned')}
                      title={$t('face_unassigned')}
                      widthStyle="90px"
                      heightStyle="90px"
                    />
                  {:then data}
                    <ImageThumbnail
                      curve
                      shadow
                      url={data === null ? '/src/lib/assets/no-thumbnail.png' : data}
                      altText={$t('face_unassigned')}
                      title={$t('face_unassigned')}
                      widthStyle="90px"
                      heightStyle="90px"
                    />
                  {/await}
                {/if}
              </div>

              {#if !selectedPersonToCreate[face.id]}
                <p class="relative mt-1 truncate font-medium" title={personName}>
                  {#if selectedPersonToReassign[face.id]?.id}
                    {selectedPersonToReassign[face.id]?.name}
                  {:else}
                    <span class={personName === $t('face_unassigned') ? 'dark:text-gray-500' : ''}>{personName}</span>
                  {/if}
                </p>
              {/if}

              <div class="absolute -end-[3px] -top-[3px] h-[20px] w-[20px] rounded-full">
                {#if selectedPersonToCreate[face.id] || selectedPersonToReassign[face.id]}
                  <IconButton
                    shape="round"
                    variant="ghost"
                    color="primary"
                    icon={mdiRestart}
                    aria-label={$t('reset')}
                    size="small"
                    class="absolute start-1/2 top-1/2 translate-x-[-50%] translate-y-[-50%] transform"
                    onclick={() => handleReset(face.id)}
                  />
                {:else}
                  <IconButton
                    shape="round"
                    color="primary"
                    icon={mdiPencil}
                    aria-label={$t('select_new_face')}
                    size="small"
                    class="absolute start-1/2 top-1/2 translate-x-[-50%] translate-y-[-50%] transform"
                    onclick={() => handleFacePicker(face)}
                  />
                {/if}
              </div>
              <div class="absolute end-[33px] -top-[3px] h-[20px] w-[20px] rounded-full">
                {#if !selectedPersonToCreate[face.id] && !selectedPersonToReassign[face.id] && !face.person}
                  <div
                    class="flex place-content-center place-items-center rounded-full bg-[#d3d3d3] p-1 transition-all absolute start-1/2 top-1/2 translate-x-[-50%] translate-y-[-50%] transform"
                  >
                    <Icon color="primary" path={mdiAccountOff} ariaHidden size="24" />
                  </div>
                {/if}
              </div>
              {#if face.person != null}
                <div class="absolute -end-[3px] top-[33px] h-[20px] w-[20px] rounded-full">
                  <IconButton
                    shape="round"
                    color="danger"
                    icon={mdiTrashCan}
                    aria-label={$t('delete_face')}
                    size="small"
                    class="absolute start-1/2 top-1/2 translate-x-[-50%] translate-y-[-50%] transform"
                    onclick={() => deleteAssetFace(face)}
                  />
                </div>
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </div>
  </div>
</section>

{#if showSelectedFaces && editedFace}
  <AssignFaceSidePanel
    {editedFace}
    {assetId}
    {assetType}
    onClose={() => (showSelectedFaces = false)}
    onCreatePerson={handleCreatePerson}
    onReassign={handleReassignFace}
  />
{/if}
